import Foundation
import CoPartnerCore
// 設計：v2.1 §4.3（交棒時序）+ §E（prompt caching 穩定前綴）。組請求給 Claude computer-use。
//
// ✅ 2026-08-16 已對齊 live computer-use 契約（platform.claude.com 的 computer-use-tool 文件）：
//    開發時暫定的 betaHeader `computer-use-2025-11-24` 與 toolType `computer_20251124`
//    **經查證正確、無需修改**。真正的缺口是 builder 少了 API 必填欄位
//    （name / display_width_px / display_height_px），只帶 header 與 type 組不出合法請求。本次補齊。
//
// ⚠️ 這些常數會隨 SDK 演進——重新對齊時查該文件的 Compatibility 區塊。

public struct HandoffRequest: Sendable, Equatable {
    public let model: String
    public let betaHeader: String
    public let toolType: String
    public let toolName: String
    public let displayWidthPx: Int
    public let displayHeightPx: Int
    public let enableZoom: Bool
    public let stablePrefix: [String]   // [system, reference]：穩定、放最前面命中 prompt cache
    public let volatileSuffix: String   // envelope 劇本序列化：易變、放最後（不打斷 cache 前綴）

    public init(model: String, betaHeader: String, toolType: String, toolName: String,
                displayWidthPx: Int, displayHeightPx: Int, enableZoom: Bool,
                stablePrefix: [String], volatileSuffix: String) {
        self.model = model
        self.betaHeader = betaHeader
        self.toolType = toolType
        self.toolName = toolName
        self.displayWidthPx = displayWidthPx
        self.displayHeightPx = displayHeightPx
        self.enableZoom = enableZoom
        self.stablePrefix = stablePrefix
        self.volatileSuffix = volatileSuffix
    }
}

public struct HandoffRequestBuilder: Sendable {
    /// 目前的 computer-use beta header（2026-08-16 查證）。
    public static let currentBetaHeader = "computer-use-2025-11-24"
    /// 目前的 computer tool 版本（2026-08-16 查證）。
    public static let currentToolType = "computer_20251124"
    /// API 規定 `name` 必須**恰好**是 "computer"——不是可自由命名的欄位。
    public static let requiredToolName = "computer"

    /// `computer_20251124` + `computer-use-2025-11-24` 的支援模型（2026-08-16 查證）。
    /// 較舊的模型（Sonnet 4.5 / Haiku 4.5 / Opus 4.1…）要改用 `computer-use-2025-01-24` header，
    /// 屬於另一份契約，本 builder 不涵蓋。
    public static let supportedModels: Set<String> = [
        "claude-opus-5", "claude-sonnet-5", "claude-opus-4-8",
        "claude-opus-4-7", "claude-opus-4-6", "claude-sonnet-4-6",
        "claude-opus-4-5-20251101",
    ]

    public let model: String
    public let betaHeader: String
    public let toolType: String
    public let toolName: String
    public let displayWidthPx: Int
    public let displayHeightPx: Int
    public let enableZoom: Bool

    /// ⚠️ `displayWidthPx` / `displayHeightPx` **刻意沒有預設值**。
    /// 它們是 API 必填欄位，而且直接決定 Claude 回傳座標的意義——填錯不會報錯，
    /// 只會讓每一次點擊都落在錯的位置，是最難查的那種 bug。強制呼叫端從真實顯示器取值。
    ///
    /// `enableZoom` 是 `computer_20251124` 新增的能力：允許 Claude 放大檢視小字
    /// （側欄檔名、分頁標題、行號）。預設關閉，開啟會增加 token 成本。
    public init(model: String = "claude-opus-5",
                displayWidthPx: Int,
                displayHeightPx: Int,
                enableZoom: Bool = false,
                betaHeader: String = HandoffRequestBuilder.currentBetaHeader,
                toolType: String = HandoffRequestBuilder.currentToolType,
                toolName: String = HandoffRequestBuilder.requiredToolName) {
        self.model = model
        self.displayWidthPx = displayWidthPx
        self.displayHeightPx = displayHeightPx
        self.enableZoom = enableZoom
        self.betaHeader = betaHeader
        self.toolType = toolType
        self.toolName = toolName
    }

    /// 這個模型是否支援目前的 computer tool 版本。送出前檢查——
    /// 不支援的模型會被 API 拒絕，早點發現比拿到 400 好。
    public var isModelSupported: Bool { Self.supportedModels.contains(model) }

    public func build(envelope: ContextEnvelope, systemPrompt: String, referencePrefix: String) -> HandoffRequest {
        HandoffRequest(model: model,
                       betaHeader: betaHeader,
                       toolType: toolType,
                       toolName: toolName,
                       displayWidthPx: displayWidthPx,
                       displayHeightPx: displayHeightPx,
                       enableZoom: enableZoom,
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
