import Foundation
import CoPartnerCore
// 設計：v2.1 §4.3（交棒時序）+ §E（prompt caching 穩定前綴）。組請求給 Claude computer-use。
// ⚠️ betaHeader / toolType 為當下已知值，**須於 🔒 step 53 對齊 live computer-use 契約**
//    （本次開發環境無法連 docs 驗證，故設計成可注入常數：屆時改預設即可，不動邏輯與測試）。

public struct HandoffRequest: Sendable, Equatable {
    public let betaHeader: String
    public let toolType: String
    public let stablePrefix: [String]   // [system, reference]：穩定、放最前面命中 prompt cache
    public let volatileSuffix: String   // envelope 劇本序列化：易變、放最後（不打斷 cache 前綴）
    public init(betaHeader: String, toolType: String, stablePrefix: [String], volatileSuffix: String) {
        self.betaHeader = betaHeader
        self.toolType = toolType
        self.stablePrefix = stablePrefix
        self.volatileSuffix = volatileSuffix
    }
}

public struct HandoffRequestBuilder: Sendable {
    public let betaHeader: String
    public let toolType: String

    public init(betaHeader: String = "computer-use-2025-11-24",
                toolType: String = "computer_20251124") {
        self.betaHeader = betaHeader
        self.toolType = toolType
    }

    public func build(envelope: ContextEnvelope, systemPrompt: String, referencePrefix: String) -> HandoffRequest {
        HandoffRequest(betaHeader: betaHeader,
                       toolType: toolType,
                       stablePrefix: [systemPrompt, referencePrefix],
                       volatileSuffix: Self.serializeScript(envelope))
    }

    /// 易變的劇本主體序列化成一段文字（token 便宜、放 cache 前綴之後）。
    static func serializeScript(_ e: ContextEnvelope) -> String {
        var lines = ["session_summary: \(e.actionScript.sessionSummary)",
                     "open_loop: \(e.actionScript.openLoop)"]
        for s in e.actionScript.recentSteps {
            lines.append("- [\(s.category)] \(s.whatHappened) → \(s.inferredGoal)")
        }
        return lines.joined(separator: "\n")
    }
}
