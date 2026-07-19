import Foundation
// 設計：§J（M0 量化驗收）。量測 harness 的統計聚合（純值、CI 可測）。
// CPU% 於真機以活動監視器 / Instruments 讀（step 18）；此處聚合延遲、吞吐、dirty tile 數。

/// 延遲樣本聚合（ring buffer 上限）。
public struct LatencySamples: Sendable, Equatable {
    private var samples: [Double] = []
    public let capacity: Int
    public init(capacity: Int = 10_000) { self.capacity = max(1, capacity) }

    public var count: Int { samples.count }

    public mutating func record(_ seconds: Double) {
        samples.append(seconds)
        if samples.count > capacity { samples.removeFirst(samples.count - capacity) }
    }

    public var mean: Double {
        guard !samples.isEmpty else { return 0 }
        return samples.reduce(0, +) / Double(samples.count)
    }

    /// 最近排名百分位（p∈[0,1]）。
    public func percentile(_ p: Double) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sorted = samples.sorted()
        let clamped = min(max(p, 0), 1)
        let index = Int((clamped * Double(sorted.count - 1)).rounded())
        return sorted[index]
    }
}

/// 擷取量測：幀數、dirty tile 累計、每幀處理延遲分佈。
public struct CaptureMetrics: Sendable, Equatable {
    public private(set) var frameCount = 0
    public private(set) var dirtyTileCount = 0
    public private(set) var latency = LatencySamples()
    public init() {}

    public mutating func recordFrame(latencySeconds: Double, dirtyTiles: Int) {
        frameCount += 1
        dirtyTileCount += max(0, dirtyTiles)
        latency.record(latencySeconds)
    }

    public var averageDirtyTilesPerFrame: Double {
        frameCount == 0 ? 0 : Double(dirtyTileCount) / Double(frameCount)
    }

    /// 一行 dump（供真機 log）。
    public func summary() -> String {
        guard frameCount > 0 else { return "量測：尚無幀" }
        func ms(_ s: Double) -> String { String(format: "%.1f", s * 1000) }
        return "量測：\(frameCount) 幀、平均 \(String(format: "%.2f", averageDirtyTilesPerFrame)) dirty tile/幀、"
            + "延遲 mean \(ms(latency.mean))ms / p50 \(ms(latency.percentile(0.5)))ms / p95 \(ms(latency.percentile(0.95)))ms"
    }
}
