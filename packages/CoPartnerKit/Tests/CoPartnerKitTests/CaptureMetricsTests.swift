import XCTest
import CaptureEngine

/// 量測 harness 統計聚合（§J）。CPU% 真機讀，此處驗延遲/吞吐聚合。
final class CaptureMetricsTests: XCTestCase {
    func testLatencyPercentilesAndMean() {
        var s = LatencySamples()
        for v in [0.010, 0.020, 0.030, 0.040, 0.050] { s.record(v) }
        XCTAssertEqual(s.count, 5)
        XCTAssertEqual(s.mean, 0.030, accuracy: 1e-9)
        XCTAssertEqual(s.percentile(0.5), 0.030, accuracy: 1e-9)   // round(0.5*4)=2 → 0.030
        XCTAssertEqual(s.percentile(0), 0.010, accuracy: 1e-9)
        XCTAssertEqual(s.percentile(1), 0.050, accuracy: 1e-9)
    }

    func testLatencyRingCapDropsOldest() {
        var s = LatencySamples(capacity: 3)
        for v in [1.0, 2.0, 3.0, 4.0] { s.record(v) }
        XCTAssertEqual(s.count, 3)
        XCTAssertEqual(s.percentile(0), 2.0, accuracy: 1e-9)   // 1.0 已被丟
    }

    func testEmptyLatencyIsZero() {
        let s = LatencySamples()
        XCTAssertEqual(s.mean, 0)
        XCTAssertEqual(s.percentile(0.9), 0)
    }

    func testMetricsAggregation() {
        var m = CaptureMetrics()
        m.recordFrame(latencySeconds: 0.01, dirtyTiles: 3)
        m.recordFrame(latencySeconds: 0.03, dirtyTiles: 5)
        XCTAssertEqual(m.frameCount, 2)
        XCTAssertEqual(m.dirtyTileCount, 8)
        XCTAssertEqual(m.averageDirtyTilesPerFrame, 4.0, accuracy: 1e-9)
    }

    func testEmptyMetricsSummary() {
        XCTAssertTrue(CaptureMetrics().summary().contains("尚無"))
    }
}
