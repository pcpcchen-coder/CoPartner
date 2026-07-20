import Foundation
import CoPartnerCore
// 設計：docs/design/v2.1_action-script-narrator.md §3（熱劇本＝最近 5–15 min，RAM ring buffer）。
// 容量上限（環狀，超量丟最舊）＋ 時間窗（查詢時濾掉過期）雙重淘汰。純邏輯、CI 可測。

/// L1 熱層：最近的 L0 原始行與 L1 `ActionStep`，RAM 環狀緩衝。
/// L0 與 steps 各自獨立環，互不牽動。
public struct L1HotBuffer: Sendable {
    private var steps: [(step: ActionStep, at: Date)] = []
    private var l0: [(line: String, at: Date)] = []
    private let capacity: Int
    private let window: TimeInterval

    public init(capacity: Int = 512, window: TimeInterval = 900) {   // 預設 15 min
        self.capacity = max(1, capacity)
        self.window = max(0, window)
    }

    public mutating func append(_ step: ActionStep, at time: Date) {
        steps.append((step, time))
        if steps.count > capacity { steps.removeFirst(steps.count - capacity) }
    }

    public mutating func appendL0(_ line: String, at time: Date) {
        l0.append((line, time))
        if l0.count > capacity { l0.removeFirst(l0.count - capacity) }
    }

    /// 時間窗內的 step（最舊→最新）。
    public func recentSteps(now: Date) -> [ActionStep] {
        let cutoff = now.addingTimeInterval(-window)
        return steps.filter { $0.at >= cutoff }.map { $0.step }
    }

    /// 時間窗內的 L0 原始行（最舊→最新）。
    public func recentL0(now: Date) -> [String] {
        let cutoff = now.addingTimeInterval(-window)
        return l0.filter { $0.at >= cutoff }.map { $0.line }
    }

    public var count: Int { steps.count }
    public var l0Count: Int { l0.count }
}
