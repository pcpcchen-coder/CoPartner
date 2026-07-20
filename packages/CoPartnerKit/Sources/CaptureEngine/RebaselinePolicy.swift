import Foundation
// 設計：docs/design/v2_smart-capture-engine.md §B.7（每 T 秒 或 累積 delta 覆蓋 > X% → re-baseline 存新 I-frame）。
// 純決策：吃「距上次 baseline 的秒數」與 ReferenceDeltaStore.pendingDeltaCoverage。CI 可測。

public enum RebaselineReason: Sendable, Equatable {
    case timeExceeded        // 距上次 baseline ≥ maxInterval
    case coverageExceeded    // 累積 delta 覆蓋 ≥ maxCoverage
}

public enum RebaselineDecision: Sendable, Equatable {
    case keep
    case rebaseline(reason: RebaselineReason)
}

public struct RebaselinePolicy: Sendable {
    public let maxInterval: TimeInterval    // 幾秒強制 re-baseline
    public let maxCoverage: Double          // 覆蓋率門檻 [0,1]

    public init(maxInterval: TimeInterval = 30, maxCoverage: Double = 0.6) {
        self.maxInterval = maxInterval
        self.maxCoverage = maxCoverage
    }

    /// 時間優先、其次覆蓋率；門檻採 ≥（含邊界）。
    public func decision(sinceLastBaseline: TimeInterval, coverage: Double) -> RebaselineDecision {
        if sinceLastBaseline >= maxInterval { return .rebaseline(reason: .timeExceeded) }
        if coverage >= maxCoverage { return .rebaseline(reason: .coverageExceeded) }
        return .keep
    }
}
