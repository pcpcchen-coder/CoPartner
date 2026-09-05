import XCTest
import CoreGraphics
@testable import CaptureEngine

/// 敏感偵測的讀數可不可信（step 61）。
///
/// 這一組存在的理由是一次真機 fail-open：報告寫「敏感 tile：0／135（0.0%）」，
/// 政策判「可送」，而畫面上是一個沒有被塗黑的登入頁。那個 `0` 不是
/// 「看清楚了，沒有密碼欄」，是「根本沒看到控制項」——兩者在數字上無法區分。
final class SensitiveMaskEvidenceTests: XCTestCase {

    private func element(role: String, subrole: String? = nil, pid: Int32? = 100)
        -> AXFocusedElement {
        AXFocusedElement(role: role, subrole: subrole,
                         frame: CGRect(x: 0, y: 0, width: 10, height: 10),
                         value: nil, windowTitle: nil, ownerPID: pid)
    }

    private func reasons(_ e: AXFocusedElement?, front: Int32? = 100, tiles: Int = 135) -> [String] {
        SensitiveMaskEvidence.unusableReasons(focused: e, frontmostPID: front, gridTileCount: tiles)
    }

    /// 正常情況：最前景 app 的一個真控制項 → 讀數可信。
    func testControlInFrontmostAppIsUsable() {
        XCTAssertEqual(reasons(element(role: "AXTextField")), [])
        XCTAssertEqual(reasons(element(role: "AXSecureTextField")), [])
    }

    /// **真機那次的形狀。** 焦點是視窗而不是控制項 → 不可信。
    func testWindowRoleIsNotEvidence() {
        let r = reasons(element(role: "AXWindow", subrole: "AXSystemDialog"))
        XCTAssertEqual(r.count, 1)
        XCTAssertTrue(r[0].contains("AXWindow"), r[0])
        XCTAssertTrue(r[0].contains("AXSystemDialog"), r[0])
    }

    /// 瀏覽器的網頁根節點同樣不算證據——整個網頁在 AX 上是一個不透明節點，
    /// 裡面的密碼欄**永遠不會**以 `AXSecureTextField` 出現。
    func testWebAreaIsNotEvidence() {
        XCTAssertFalse(reasons(element(role: "AXWebArea")).isEmpty)
    }

    func testMissingFocusIsNotEvidence() {
        XCTAssertFalse(reasons(nil).isEmpty)
    }

    /// 格線沒建起來 → 遮罩不可能有內容，讀數不可信。
    func testDegenerateGridIsNotEvidence() {
        XCTAssertFalse(reasons(element(role: "AXTextField"), tiles: 0).isEmpty)
    }

    /// 焦點屬於別的程序 → 我們量的不是使用者正在看的視窗。
    func testOwnerMismatchIsNotEvidence() {
        let r = reasons(element(role: "AXTextField", pid: 2239), front: 501)
        XCTAssertEqual(r.count, 1)
        XCTAssertTrue(r[0].contains("2239") && r[0].contains("501"), r[0])
    }

    /// 對不了帳也是不可信——「問不到」跟「對得上」不是同一件事。
    func testUnknownPIDsAreNotEvidence() {
        XCTAssertFalse(reasons(element(role: "AXTextField", pid: nil)).isEmpty)
        XCTAssertFalse(reasons(element(role: "AXTextField"), front: nil).isEmpty)
    }

    /// **所有**成立的理由都要回報，不是只回第一條。真機那次同時命中兩條，
    /// 只講一條會讓下一輪修錯地方。
    func testAllReasonsAreReported() {
        let r = reasons(element(role: "AXWindow", pid: 2239), front: 501, tiles: 0)
        XCTAssertEqual(r.count, 3, r.joined(separator: " / "))
    }
}
