import XCTest
import CoPartnerCore
import CaptureEngine

/// OCR / 持久化節流決策（§B.6）。
final class CaptureThrottleTests: XCTestCase {
    func testColdSkipsOCR() {
        XCTAssertFalse(CaptureThrottle().shouldOCR(state: .cold, sinceLastOCR: 100))
    }

    func testWarmRunsOCR() {
        XCTAssertTrue(CaptureThrottle().shouldOCR(state: .warm, sinceLastOCR: 0))
    }

    func testDynamicSkipsOCR() {
        XCTAssertFalse(CaptureThrottle().shouldOCR(state: .dynamic, sinceLastOCR: 100))
    }

    func testHotThrottled() {
        let t = CaptureThrottle(hotOCRInterval: 0.5)
        XCTAssertFalse(t.shouldOCR(state: .hot, sinceLastOCR: 0.3))   // 太快 → 跳
        XCTAssertTrue(t.shouldOCR(state: .hot, sinceLastOCR: 0.5))    // 到間隔 → 跑
    }

    func testPersistDeltaExceptDynamic() {
        let t = CaptureThrottle()
        XCTAssertTrue(t.shouldPersistDelta(state: .warm))
        XCTAssertTrue(t.shouldPersistDelta(state: .hot))
        XCTAssertTrue(t.shouldPersistDelta(state: .cold))
        XCTAssertFalse(t.shouldPersistDelta(state: .dynamic))   // 影片不存 delta
    }

    /// 模擬 spy：跑一串狀態，數實際觸發 OCR 的次數。
    func testOCRCallCountOverSequence() {
        let t = CaptureThrottle(hotOCRInterval: 0.5)
        let sequence: [(TileEvent.State, TimeInterval)] = [
            (.cold, 100), (.warm, 0), (.hot, 0.1), (.hot, 0.6), (.dynamic, 100), (.warm, 0),
        ]
        let ocrCalls = sequence.filter { t.shouldOCR(state: $0.0, sinceLastOCR: $0.1) }.count
        XCTAssertEqual(ocrCalls, 3)   // warm、hot@0.6、warm
    }
}
