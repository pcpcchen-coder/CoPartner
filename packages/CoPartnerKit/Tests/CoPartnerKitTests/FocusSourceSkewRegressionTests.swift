import XCTest
import ScriptNarrator

/// step 54 dogfood 第二輪真機回歸：**兩個獨立來源在切換瞬間不同步**。
///
/// app 名稱來自 NSWorkspace，視窗標題來自 AX。切 app 的那一瞬間 AX 已經指到新 app，
/// NSWorkspace 還說舊 app，於是欄位被湊成一個從來不存在的組合：
///
///   [22:22:58.065] FOCUS  app=備忘錄 win="新增連線"   ← "新增連線" 是 AnyDesk 的視窗
///   [22:22:58.067] SWITCH app=AnyDesk win="新增連線"  ← 2ms 後 NSWorkspace 才跟上
///
/// 前面那筆是假的。這是 FocusChangeTracker 系列的**第四種**成因：
/// 前三種是「拿錯東西當身分」，這種是「兩個欄位不是在講同一個 app」。
final class FocusSourceSkewRegressionTests: XCTestCase {

    // MARK: - 對帳規則本身

    /// 擁有者對不上 → 當作沒讀到標題。
    func testMismatchedOwnerYieldsUnknownTitle() {
        let window = FocusChangeTracker.reconciledWindow(
            frontmostApp: "備忘錄", axOwnerApp: "AnyDesk",
            axWindowTitle: "新增連線", axRoleFallback: "AXTextArea")
        XCTAssertTrue(FocusChangeTracker.isUnknownTitle(window),
                      "兩個來源在講不同的 app，標題不可信")
    }

    /// 擁有者對得上 → 照常使用標題。
    func testMatchingOwnerKeepsTitle() {
        XCTAssertEqual(
            FocusChangeTracker.reconciledWindow(
                frontmostApp: "AnyDesk", axOwnerApp: "AnyDesk",
                axWindowTitle: "新增連線", axRoleFallback: "AXTextArea"),
            "新增連線")
    }

    /// 讀不到擁有者是**資訊不足**，不是矛盾——不可因此擋掉標題，
    /// 否則所有讀不到 pid 的 app 永遠不產生 FOCUS（漏記比噪音更糟）。
    func testUnknownOwnerDoesNotBlockTitle() {
        XCTAssertEqual(
            FocusChangeTracker.reconciledWindow(
                frontmostApp: "Xcode", axOwnerApp: nil,
                axWindowTitle: "A.swift", axRoleFallback: "AXTextArea"),
            "A.swift")
    }

    /// 沒有標題時退回 role（既有行為，不可被這次改動弄丟）。
    func testFallsBackToRoleWhenNoTitle() {
        XCTAssertEqual(
            FocusChangeTracker.reconciledWindow(
                frontmostApp: "SomeApp", axOwnerApp: "SomeApp",
                axWindowTitle: nil, axRoleFallback: "AXTextArea"),
            "AXTextArea")
        XCTAssertEqual(
            FocusChangeTracker.reconciledWindow(
                frontmostApp: "SomeApp", axOwnerApp: "SomeApp",
                axWindowTitle: nil, axRoleFallback: nil),
            "")
    }

    // MARK: - 接上 tracker：真機序列重演

    /// 對帳 + 「未知不是新視窗」合起來，整段不同步應該一筆假 FOCUS 都不產生。
    func testSkewDuringAppSwitchEmitsNoPhantomFocus() {
        var tracker = FocusChangeTracker()
        func observe(frontmost: String, owner: String?, title: String?) -> L0Event? {
            tracker.event(app: frontmost,
                          window: FocusChangeTracker.reconciledWindow(
                            frontmostApp: frontmost, axOwnerApp: owner,
                            axWindowTitle: title, axRoleFallback: nil))
        }

        _ = observe(frontmost: "備忘錄", owner: "備忘錄", title: "所有 iCloud — 167則備忘錄")
        // 使用者點進 AnyDesk：AX 先跟上，NSWorkspace 還沒。
        XCTAssertNil(observe(frontmost: "備忘錄", owner: "AnyDesk", title: "新增連線"),
                     "兩個來源不同步，不該產生 FOCUS")
        // 2ms 後 NSWorkspace 跟上 → 這才是真的 SWITCH。
        XCTAssertEqual(observe(frontmost: "AnyDesk", owner: "AnyDesk", title: "新增連線"),
                       .switchApp(app: "AnyDesk", window: "新增連線"))
        // 之後在 AnyDesk 裡真的換視窗仍要記。
        XCTAssertEqual(observe(frontmost: "AnyDesk", owner: "AnyDesk", title: "遠端桌面"),
                       .focus(app: "AnyDesk", window: "遠端桌面"))
    }

    /// 不同步結束後資訊不會遺失：下一次觀測兩邊一致，身分就補回來了。
    func testInformationIsNotLostAfterSkewResolves() {
        var tracker = FocusChangeTracker()
        _ = tracker.event(app: "AnyDesk", window: "")                    // 進場，標題還沒好
        _ = tracker.event(app: "AnyDesk", window: "")                    // 不同步期間一律未知
        XCTAssertNil(tracker.event(app: "AnyDesk", window: "新增連線"),
                     "未知 → 已知只是補上資訊")
        XCTAssertEqual(tracker.event(app: "AnyDesk", window: "遠端桌面"),
                       .focus(app: "AnyDesk", window: "遠端桌面"),
                       "身分已經補回來了，真的換視窗仍記得到")
    }
}
