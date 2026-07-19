import XCTest
import CaptureEngine

/// 每 app override（§L）：排除 DYNAMIC 判定。
final class CaptureOverridesTests: XCTestCase {
    func testDefaultAllowsDynamic() {
        XCTAssertTrue(CaptureOverrides().allowsDynamic(app: "Safari"))
    }

    func testMarkedAppDisallowsDynamic() {
        var o = CaptureOverrides()
        o.setNeverDynamic("StockTicker")
        XCTAssertFalse(o.allowsDynamic(app: "StockTicker"))
        XCTAssertTrue(o.allowsDynamic(app: "Safari"))   // 其他不受影響
    }

    func testUnsetRestoresDynamic() {
        var o = CaptureOverrides(neverDynamicApps: ["Clock"])
        XCTAssertFalse(o.allowsDynamic(app: "Clock"))
        o.setNeverDynamic("Clock", false)
        XCTAssertTrue(o.allowsDynamic(app: "Clock"))
    }

    func testListIsSorted() {
        var o = CaptureOverrides()
        o.setNeverDynamic("Zeta")
        o.setNeverDynamic("Alpha")
        XCTAssertEqual(o.neverDynamicList, ["Alpha", "Zeta"])
    }
}
