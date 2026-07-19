import XCTest
import CaptureEngine

/// DYNAMIC 週期性偵測（§B.6）。合成時間序列，決定性。
final class PeriodicityDetectorTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)

    func testRegular60fpsIsPeriodic() {
        var d = PeriodicityDetector(minRate: 10, minSamples: 5)
        var result = false
        for i in 0..<8 { result = d.record(t0.addingTimeInterval(Double(i) / 60.0)) }
        XCTAssertTrue(result)
    }

    func testTooFewSamplesNotPeriodic() {
        var d = PeriodicityDetector(minSamples: 5)
        var result = false
        for i in 0..<3 { result = d.record(t0.addingTimeInterval(Double(i) / 60.0)) }   // 僅 2 個間隔
        XCTAssertFalse(result)
    }

    func testIrregularStreamNotPeriodic() {
        var d = PeriodicityDetector()
        var result = true
        for t in [0.0, 0.5, 0.55, 2.0, 2.1, 3.9, 4.0, 8.0] {
            result = d.record(t0.addingTimeInterval(t))
        }
        XCTAssertFalse(result)
    }

    func testRegularHighRatePure() {
        XCTAssertTrue(PeriodicityDetector.isPeriodic(
            intervals: Array(repeating: 1.0 / 60.0, count: 6), minRate: 10, maxCV: 0.25, minSamples: 5))
    }

    func testSlowButRegularBelowMinRate() {
        // 2fps 很規律但太慢 → 不算影片
        XCTAssertFalse(PeriodicityDetector.isPeriodic(
            intervals: Array(repeating: 0.5, count: 6), minRate: 10, maxCV: 0.25, minSamples: 5))
    }

    func testHighVarianceNotPeriodic() {
        XCTAssertFalse(PeriodicityDetector.isPeriodic(
            intervals: [0.016, 0.05, 0.01, 0.08, 0.012, 0.09], minRate: 10, maxCV: 0.25, minSamples: 5))
    }
}
