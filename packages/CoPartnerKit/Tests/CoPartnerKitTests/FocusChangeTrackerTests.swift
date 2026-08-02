import XCTest
import ScriptNarrator

/// 焦點追蹤 → FOCUS / SWITCH 事件（§B.4）。
final class FocusChangeTrackerTests: XCTestCase {
    func testFirstObservationEmitsSwitch() {
        var tracker = FocusChangeTracker()
        guard case .switchApp(let app, let window)? = tracker.event(app: "Xcode", window: "A.swift") else {
            return XCTFail("首次觀測應視為 SWITCH")
        }
        XCTAssertEqual(app, "Xcode")
        XCTAssertEqual(window, "A.swift")
    }

    func testSameAppNewWindowEmitsFocus() {
        var tracker = FocusChangeTracker()
        _ = tracker.event(app: "Xcode", window: "A.swift")
        guard case .focus(let app, let window)? = tracker.event(app: "Xcode", window: "B.swift") else {
            return XCTFail("同 app 換視窗應為 FOCUS")
        }
        XCTAssertEqual(app, "Xcode")
        XCTAssertEqual(window, "B.swift")
    }

    func testDifferentAppEmitsSwitch() {
        var tracker = FocusChangeTracker()
        _ = tracker.event(app: "Xcode", window: "A.swift")
        guard case .switchApp? = tracker.event(app: "Safari", window: "Google") else {
            return XCTFail("換 app 應為 SWITCH")
        }
    }

    func testNoChangeEmitsNil() {
        var tracker = FocusChangeTracker()
        _ = tracker.event(app: "Xcode", window: "A.swift")
        XCTAssertNil(tracker.event(app: "Xcode", window: "A.swift"))
    }
}
