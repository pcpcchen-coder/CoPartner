import Foundation
import CoPartnerCore
// SSE frame → Claude Messages API 的串流語意 → 完成的 tool_use（正規化後交給 parser）。
//
// 為什麼需要累積器而不是逐事件處理：tool_use 的 `input` 是**跨多個事件分批送**的
// （`input_json_delta` 的 `partial_json` 每次只有一小段，可能切在 JSON token 中間），
// 必須全部收齊才能 JSON 解析。逐事件解析必然失敗。
//
// 事件序列（Messages API 串流）：
//   content_block_start  { index, content_block: {type:"tool_use", id, name, input:{}} }
//   content_block_delta  { index, delta: {type:"input_json_delta", partial_json:"{\"acti"} }
//   content_block_delta  { index, delta: {type:"input_json_delta", partial_json:"on\":...} }
//   content_block_stop   { index }                       ← 此時才 JSON 解析
//
// 文字區塊（text_delta）累積成 rationale：Claude 通常會先說明再動作，那段說明就是
// 「為什麼要做這個動作」——HUD 要顯示給使用者看（威脅模型：提議要可判讀才談得上確認）。

public enum AnthropicStreamDecodeError: Error, Equatable {
    /// tool_use 的 input 收齊後仍不是合法 JSON 物件。
    case malformedToolInput(String)
}

/// 一個收齊的 tool_use：工具名 + 已解析的 input + 之前累積的說明文字。
///
/// ⚠️ **刻意不是 Sendable**：`input` 是 `[String: Any]`（JSON 的自然形狀），
/// 本質上無法保證 Sendable。它只在單一 Task 內產生並立刻消費掉，不跨隔離邊界，
/// 所以不需要——硬加 `@unchecked Sendable` 只會把編譯器的正確警告消音。
public struct DecodedToolUse {
    public let toolName: String
    public let input: [String: Any]
    public let rationale: String
    public init(toolName: String, input: [String: Any], rationale: String) {
        self.toolName = toolName
        self.input = input
        self.rationale = rationale
    }
}

/// 把 SSE frame 餵進來，吐出收齊的 tool_use。
public struct AnthropicStreamDecoder: Sendable {
    /// 進行中的內容區塊，依 `index` 追蹤——同一則訊息可以有多個平行區塊。
    private struct Block {
        var type: String
        var toolName: String?
        var jsonParts: [String] = []
        var textParts: [String] = []
    }
    private var blocks: [Int: Block] = [:]
    /// 目前訊息累積到的說明文字，當作後續 tool_use 的 rationale。
    private var rationale = ""
    /// 串流回報的 stop_reason（`tool_use` 表示 Claude 要我們動作）。
    public private(set) var stopReason: String?

    public init() {}

    /// 餵一個 SSE frame，回傳這個 frame 讓哪些 tool_use 收齊（通常 0 或 1 個）。
    public mutating func feed(_ frame: SSEFrame) throws -> [DecodedToolUse] {
        guard let data = frame.data.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else {
            return []      // 非 JSON 或無 type：忽略（例如 ping）
        }

        switch type {
        case "content_block_start":
            guard let index = intValue(obj["index"]),
                  let cb = obj["content_block"] as? [String: Any],
                  let blockType = cb["type"] as? String else { return [] }
            blocks[index] = Block(type: blockType, toolName: cb["name"] as? String)
            return []

        case "content_block_delta":
            guard let index = intValue(obj["index"]),
                  let delta = obj["delta"] as? [String: Any],
                  let deltaType = delta["type"] as? String else { return [] }
            if deltaType == "input_json_delta", let part = delta["partial_json"] as? String {
                blocks[index]?.jsonParts.append(part)
            } else if deltaType == "text_delta", let text = delta["text"] as? String {
                blocks[index]?.textParts.append(text)
            }
            return []

        case "content_block_stop":
            guard let index = intValue(obj["index"]), let block = blocks.removeValue(forKey: index) else {
                return []
            }
            if block.type == "text" {
                // 說明文字收齊 → 成為後續動作的 rationale。
                let text = block.textParts.joined()
                if !text.isEmpty { rationale = text }
                return []
            }
            guard block.type == "tool_use", let toolName = block.toolName else { return [] }
            return [try finishToolUse(block: block, toolName: toolName)]

        case "message_delta":
            if let delta = obj["delta"] as? [String: Any],
               let reason = delta["stop_reason"] as? String {
                stopReason = reason
            }
            return []

        default:
            return []      // message_start / message_stop / ping 等：無需處理
        }
    }

    private func finishToolUse(block: Block, toolName: String) throws -> DecodedToolUse {
        let joined = block.jsonParts.joined()
        // input 為空物件時 Anthropic 可能一個 delta 都不送——空字串當作 {}，不是錯誤。
        if joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return DecodedToolUse(toolName: toolName, input: [:], rationale: rationale)
        }
        guard let data = joined.data(using: .utf8),
              let input = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AnthropicStreamDecodeError.malformedToolInput(joined)
        }
        return DecodedToolUse(toolName: toolName, input: input, rationale: rationale)
    }

    private func intValue(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let d = any as? Double { return Int(d) }
        return nil
    }
}

/// SSE 位元組來源。真 HTTP 在此注入（🔒 待接）；CI 用重播固定腳本的假來源。
///
/// 設計成「吐文字片段」而非「吐完整 frame」是刻意的——真網路的 chunk 邊界是任意的，
/// 假來源必須能重現「frame 被切成兩半」這種情況，否則測不到真正會出錯的地方。
public protocol SSEByteSource: Sendable {
    func chunks(for request: HandoffRequest) -> AsyncThrowingStream<String, Error>
}

/// 把 SSE 位元組流組成 `ProposedAction` 串流的 transport。
///
/// 全鏈：位元組 → `SSEFrameParser`（框架）→ `AnthropicStreamDecoder`（語意）
/// → `ComputerUseNormalizer`（形狀）→ `ProposedActionParser`（型別）。
/// 每一層各自可測，壞掉時知道是哪一層。
public struct SSEHandoffTransport: HandoffTransport {
    private let source: any SSEByteSource
    /// 解析不出來的動作要不要中止整個串流。
    /// 預設 `false`：跳過不認得的提議、繼續處理其餘的——單一個不支援的動作
    /// （例如 Claude 送了 zoom）不該讓整次接手作廢。
    private let failOnUnparsableAction: Bool

    public init(source: any SSEByteSource, failOnUnparsableAction: Bool = false) {
        self.source = source
        self.failOnUnparsableAction = failOnUnparsableAction
    }

    public func stream(_ request: HandoffRequest) -> AsyncThrowingStream<ProposedAction, Error> {
        let source = self.source
        let failFast = self.failOnUnparsableAction
        return AsyncThrowingStream { continuation in
            let task = Task {
                var parser = SSEFrameParser()
                var decoder = AnthropicStreamDecoder()
                do {
                    for try await chunk in source.chunks(for: request) {
                        for frame in parser.feed(chunk) {
                            try Self.emit(frame: frame, decoder: &decoder,
                                          failFast: failFast, into: continuation)
                        }
                    }
                    if let last = parser.finish() {
                        try Self.emit(frame: last, decoder: &decoder,
                                      failFast: failFast, into: continuation)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// static：避免在 Task 閉包裡捕獲 self（沒必要，且讓 Sendable 檢查更單純）。
    private static func emit(frame: SSEFrame,
                             decoder: inout AnthropicStreamDecoder,
                             failFast: Bool,
                             into continuation: AsyncThrowingStream<ProposedAction, Error>.Continuation) throws {
        for toolUse in try decoder.feed(frame) {
            do {
                let normalized = try ComputerUseNormalizer.normalize(toolName: toolUse.toolName,
                                                                     input: toolUse.input)
                let action = try ProposedActionParser.parse(toolName: toolUse.toolName,
                                                            input: normalized,
                                                            rationale: toolUse.rationale)
                continuation.yield(action)
            } catch {
                if failFast { throw error }
                // 略過這一個提議。**不猜、不代換**——執行一個沒被提議過的動作
                // 比少做一個危險得多（威脅模型 I4/I9）。
            }
        }
    }
}
