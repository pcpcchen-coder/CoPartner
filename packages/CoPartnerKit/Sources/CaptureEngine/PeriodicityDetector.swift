import Foundation
// 設計：§B.6（DYNAMIC＝規律高頻大面積）。判定 tile 變動時間戳是否呈規律高頻（影片）。
// 純統計、CI 可測（合成時間序列）。供 TileStateMachine 的 periodic 輸入。

public struct PeriodicityDetector: Sendable, Equatable {
    public var minRate: Double                  // fps 下限（低於此不算影片）
    public var maxCoefficientOfVariation: Double // 間隔變異係數上限（越小越規律）
    public var minSamples: Int                   // 至少幾個「間隔」才判定
    public var window: Int                       // 保留最近幾個時間戳
    private var timestamps: [Date] = []

    public init(minRate: Double = 10, maxCoefficientOfVariation: Double = 0.25,
                minSamples: Int = 5, window: Int = 30) {
        self.minRate = minRate
        self.maxCoefficientOfVariation = maxCoefficientOfVariation
        self.minSamples = max(1, minSamples)
        self.window = max(2, window)
    }

    /// 記錄一次變動時間戳，回傳目前是否判定為週期性。
    @discardableResult
    public mutating func record(_ timestamp: Date) -> Bool {
        timestamps.append(timestamp)
        if timestamps.count > window { timestamps.removeFirst(timestamps.count - window) }
        return isPeriodic
    }

    public var isPeriodic: Bool {
        let intervals = zip(timestamps.dropFirst(), timestamps).map { $0.timeIntervalSince($1) }
        return Self.isPeriodic(intervals: intervals, minRate: minRate,
                               maxCV: maxCoefficientOfVariation, minSamples: minSamples)
    }

    /// 純判定：間隔序列是否高頻且規律。
    public static func isPeriodic(intervals: [Double], minRate: Double,
                                  maxCV: Double, minSamples: Int) -> Bool {
        guard intervals.count >= minSamples else { return false }
        guard intervals.allSatisfy({ $0 > 0 }) else { return false }    // 需嚴格遞增
        let mean = intervals.reduce(0, +) / Double(intervals.count)
        guard mean > 0, 1.0 / mean >= minRate else { return false }     // 頻率夠高
        let variance = intervals.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(intervals.count)
        return (variance.squareRoot() / mean) <= maxCV                  // 夠規律
    }
}
