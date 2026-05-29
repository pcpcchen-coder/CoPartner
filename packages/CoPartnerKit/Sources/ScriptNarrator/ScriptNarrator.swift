import Foundation
import CoPartnerCore
// 設計：docs/design/v2.1_action-script-narrator.md
// TODO(M2.5): L0 EventLog — deterministic 模板成句，無模型（§2 L0）
// TODO(M4): L1 Narrator — FoundationModels @Generable + prewarm + fallback（§2 L1, §5）
// TODO(M4): L2 Summarizer — 切 app / 每數分鐘 rollup（§2 L2）

/// L0：純模板，零模型成本。捕捉全部顯著事件。
public struct EventLog: Sendable {
    public private(set) var lines: [String] = []
    public init() {}
    public mutating func append(_ line: String) { lines.append(line) }
    /// TODO: 連續打字合併、scroll 節流、PII 遮罩（§2 表格）
}

/// L1：本地 LLM 敘事器。FoundationModels 不可用時 fallback。
public actor Narrator {
    public init() {}
    /// TODO: 接 FoundationModels.LanguageModelSession，輸出 ActionStep
    public func narrate(_ eventLogLines: [String]) async -> ActionStep? { nil }
}
