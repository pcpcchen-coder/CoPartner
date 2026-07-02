import Foundation
import CoPartnerCore
// 設計：docs/design/v2.1_action-script-narrator.md
// TODO(M2.5): L0 EventLog — deterministic 模板成句，無模型（§2 L0）
// TODO(M4): L1 Narrator — FoundationModels @Generable + prewarm + fallback（§2 L1, §5）
// TODO(M4): L2 Summarizer — 切 app / 每數分鐘 rollup（§2 L2）

/// L0：純模板，零模型成本。捕捉全部顯著事件，並套用 §2 的合併 / 節流規則。
/// PII 遮罩在事件進入前處理（step 7 PIIMasker）。
public struct EventLog: Sendable {
    public private(set) var lines: [String] = []

    /// 同欄位連續打字的合併時間窗（§2）。
    public var typeMergeWindow: TimeInterval = 2.0
    /// 同 app 同方向 scroll 的聚合時間窗（§2）。
    public var scrollAggregateWindow: TimeInterval = 1.0
    /// 格式化用時區（測試可注入 UTC）。
    public var timeZone: TimeZone = .current
    /// ring buffer 上限；超過丟最舊（避免長時間執行記憶體無限成長）。
    public var capacity: Int = 500

    /// 最近一個「可續接」的事件：其顯示起始時間 startAt 與最後更新時間 lastAt。
    private var pending: (event: L0Event, startAt: Date, lastAt: Date)?

    public init() {}

    /// 記錄一個 L0 事件。可與前一事件合併（同欄位打字續接 / 同向 scroll 聚合）時，
    /// 就地更新最後一行並沿用起始時間戳；否則新增一行。`now` 可注入以利決定性測試。
    public mutating func record(_ event: L0Event, at now: Date = Date()) {
        if let p = pending,
           let merged = mergedEvent(previous: p.event, lastAt: p.lastAt, with: event, at: now) {
            pending = (event: merged, startAt: p.startAt, lastAt: now)
            lines[lines.count - 1] = EventFormatter.line(merged, at: p.startAt, timeZone: timeZone)
            return
        }
        lines.append(EventFormatter.line(event, at: now, timeZone: timeZone))
        if capacity >= 1 && lines.count > capacity {
            lines.removeFirst(lines.count - capacity)
        }
        pending = (event: event, startAt: now, lastAt: now)
    }

    /// 回傳合併後的事件；不可合併回 nil。
    private func mergedEvent(previous: L0Event, lastAt: Date, with event: L0Event, at now: Date) -> L0Event? {
        switch (previous, event) {
        case let (.type(f1, t1), .type(f2, t2))
            where f1 == f2 && now.timeIntervalSince(lastAt) <= typeMergeWindow:
            return .type(field: f1, text: t1 + t2)               // 同欄位 2s 內續接成一句
        case let (.scroll(a1, d1, n1), .scroll(a2, d2, n2))
            where a1 == a2 && d1 == d2 && now.timeIntervalSince(lastAt) <= scrollAggregateWindow:
            return .scroll(app: a1, direction: d1, distance: n1 + n2)  // 同向 1s 內累加距離
        default:
            return nil
        }
    }
}

/// L1：本地 LLM 敘事器。FoundationModels 不可用時 fallback。
public actor Narrator {
    public init() {}
    /// TODO: 接 FoundationModels.LanguageModelSession，輸出 ActionStep
    public func narrate(_ eventLogLines: [String]) async -> ActionStep? { nil }
}
