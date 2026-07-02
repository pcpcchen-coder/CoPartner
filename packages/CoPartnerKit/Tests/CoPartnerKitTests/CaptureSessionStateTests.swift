import XCTest
import CoPartnerCore

/// 會話狀態機（觀察開關 + kill-switch）。
final class CaptureSessionStateTests: XCTestCase {
    func testStartsIdle() {
        XCTAssertEqual(CaptureSessionState().mode, .idle)
    }

    func testToggleObserveFromIdleGoesObserving() {
        var s = CaptureSessionState()
        s.toggleObserve()
        XCTAssertEqual(s.mode, .observing)
    }

    func testToggleObserveFromObservingReturnsIdle() {
        var s = CaptureSessionState()
        s.toggleObserve(); s.toggleObserve()
        XCTAssertEqual(s.mode, .idle)
    }

    func testStopAllFromObservingGoesIdle() {
        var s = CaptureSessionState()
        s.toggleObserve()
        s.stopAll()
        XCTAssertEqual(s.mode, .idle)
    }

    func testStopAllFromInterveningGoesIdle() {
        var s = CaptureSessionState()
        s.beginIntervention()
        s.stopAll()
        XCTAssertEqual(s.mode, .idle)
    }

    func testStopAllIsIdempotent() {
        var s = CaptureSessionState()
        s.stopAll(); s.stopAll()
        XCTAssertEqual(s.mode, .idle)
    }

    func testBeginInterventionEntersIntervening() {
        var s = CaptureSessionState()
        s.beginIntervention()
        XCTAssertEqual(s.mode, .intervening)
    }
}
