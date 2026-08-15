import XCTest
import CoreGraphics
import CaptureEngine
import ScriptNarrator

/// step 29 dogfood 真機回歸：焦點識別**不可**用欄位內容（value）當視窗識別。
/// 真機症狀：在終端機裡，AX value 是文字緩衝內容，每輸出一個字元就變 →
/// FocusChangeTracker 每次都判定「換視窗」→ 同一秒噴十幾行重複 FOCUS，淹沒劇本。
final class FocusIdentityRegressionTests: XCTestCase {
    private func element(value: String, windowTitle: String?) -> AXFocusedElement {
        AXFocusedElement(role: "AXTextArea", subrole: nil, frame: .zero,
                         value: value, windowTitle: windowTitle)
    }

    /// 正確識別鍵：windowTitle 不變 → 內容一直變也**不**該產生 FOCUS。
    func testContentChurnDoesNotEmitFocusWhenWindowStable() {
        var tracker = FocusChangeTracker()
        let first = element(value: "Last login: 12:21", windowTitle: "終端機 — bash")
        _ = tracker.event(app: "終端機", window: first.windowTitle ?? first.role)   // 首次進場

        // 終端機持續輸出：value 一直變，但視窗沒換。
        for line in ["Last login: 12:22", "Last login: 12:23", "$ ls -la", "$ echo hi"] {
            let e = element(value: line, windowTitle: "終端機 — bash")
            let event = tracker.event(app: "終端機", window: e.windowTitle ?? e.role)
            XCTAssertNil(event, "視窗未變、只是內容變動，不該產生 FOCUS（真機狂刷症狀）")
        }
    }

    /// 對照組：這正是修復前的錯誤做法（用 value 當識別）——證明它會狂噴。
    func testUsingValueAsIdentityWouldChurn() {
        var tracker = FocusChangeTracker()
        _ = tracker.event(app: "終端機", window: "Last login: 12:21")
        var emitted = 0
        for line in ["Last login: 12:22", "Last login: 12:23", "$ ls -la"] {
            if tracker.event(app: "終端機", window: line) != nil { emitted += 1 }
        }
        XCTAssertEqual(emitted, 3, "用 value 當識別會每次都噴——本測試釘住『不要這樣做』的理由")
    }

    /// 真的換視窗（標題變）仍要正常回報 FOCUS。
    func testRealWindowSwitchStillEmitsFocus() {
        var tracker = FocusChangeTracker()
        _ = tracker.event(app: "Xcode", window: "AppCoordinator.swift")
        let event = tracker.event(app: "Xcode", window: "MenuBarContentView.swift")
        XCTAssertEqual(event, .focus(app: "Xcode", window: "MenuBarContentView.swift"))
    }

    /// 無 windowTitle（某些 app 讀不到）時 fallback 到 role，仍保持穩定不狂刷。
    func testFallbackToRoleStaysStable() {
        var tracker = FocusChangeTracker()
        let e1 = element(value: "abc", windowTitle: nil)
        _ = tracker.event(app: "SomeApp", window: e1.windowTitle ?? e1.role)
        let e2 = element(value: "abcd", windowTitle: nil)     // 內容變、role 不變
        XCTAssertNil(tracker.event(app: "SomeApp", window: e2.windowTitle ?? e2.role))
    }
}
