import Foundation
// Server-Sent Events 的**框架**解析（與 Anthropic 語意無關，只認 SSE 本身的格式）。
// 分成獨立一層的理由：SSE 的邊界情況（跨 chunk 切斷、多行 data、心跳註解、CRLF）
// 與「Anthropic 事件語意」是兩件事，混在一起會讓兩邊都難測。
//
// 增量式：`feed(_:)` 吃任意大小的片段，回傳這次能湊出的完整 frame。
// 網路來的 chunk 邊界是任意的——**一個 frame 被切成兩半是常態，不是異常**。

/// 一個 SSE frame：`event:` 名稱（可缺）與 `data:` 內容。
public struct SSEFrame: Sendable, Equatable {
    public let event: String?
    public let data: String
    public init(event: String?, data: String) {
        self.event = event
        self.data = data
    }
}

/// 增量 SSE 解析器。持有跨 chunk 的殘餘，餵多少吐多少完整 frame。
public struct SSEFrameParser: Sendable {
    /// 還沒湊成完整行的殘餘位元組（上次 chunk 尾巴被切斷的部分）。
    private var buffer = ""
    /// 目前累積中的 frame 欄位。
    private var currentEvent: String?
    private var currentData: [String] = []

    public init() {}

    /// 餵一段（可能不完整的）文字，回傳這次湊齊的所有 frame。
    public mutating func feed(_ chunk: String) -> [SSEFrame] {
        buffer += chunk
        var frames: [SSEFrame] = []

        // 只處理已經有換行結尾的完整行；最後一段沒換行的留在 buffer 等下一個 chunk。
        while let newlineIndex = buffer.firstIndex(of: "\n") {
            var line = String(buffer[buffer.startIndex..<newlineIndex])
            buffer = String(buffer[buffer.index(after: newlineIndex)...])
            if line.hasSuffix("\r") { line.removeLast() }   // CRLF

            if line.isEmpty {
                // 空行 = frame 結束。沒有 data 的空 frame 忽略（純心跳）。
                if let frame = takeFrame() { frames.append(frame) }
                continue
            }
            if line.hasPrefix(":") { continue }             // 註解行（常用來當 keep-alive 心跳）

            let (field, value) = Self.splitField(line)
            switch field {
            case "event": currentEvent = value
            case "data":  currentData.append(value)         // 多行 data 依規範以 \n 串接
            default:      break                             // id / retry 等本專案用不到
            }
        }
        return frames
    }

    /// 串流結束時呼叫：吐出最後一個沒有以空行收尾的 frame（有些伺服器會這樣）。
    public mutating func finish() -> SSEFrame? { takeFrame() }

    private mutating func takeFrame() -> SSEFrame? {
        defer { currentEvent = nil; currentData = [] }
        guard !currentData.isEmpty else { return nil }
        return SSEFrame(event: currentEvent, data: currentData.joined(separator: "\n"))
    }

    /// `field: value`——規範規定冒號後若有**一個**空格要去掉，多的空格要保留。
    static func splitField(_ line: String) -> (field: String, value: String) {
        guard let colon = line.firstIndex(of: ":") else { return (line, "") }
        let field = String(line[line.startIndex..<colon])
        var value = String(line[line.index(after: colon)...])
        if value.hasPrefix(" ") { value.removeFirst() }
        return (field, value)
    }
}
