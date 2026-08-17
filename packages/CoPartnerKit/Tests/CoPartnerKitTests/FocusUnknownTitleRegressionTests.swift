import XCTest
import ScriptNarrator

/// step 54 dogfood 真機回歸：**AX 有時候整個讀不到視窗標題**，回空字串。
///
/// 真機症狀（截自劇本區）：
///   SWITCH app=系統設定 win=""
///   FOCUS  app=系統設定 win="隱私權與安全性"   ← "" → 有標題
///   FOCUS  app=系統設定 win=""                ← 有標題 → ""
/// 空字串被當成一個合法的視窗身分，於是標題在「讀得到 / 讀不到」之間跳的時候
/// 來回噴假 FOCUS，而那串噪音會餵進 L1。
///
/// 這是這個檔的**第三次**同類錯誤（M2：拿欄位內容當身分；M5：拿會變的標題當身分）。
/// 核心規則現在是：**只有「已知 → 另一個已知」才算換視窗。**
final class FocusUnknownTitleRegressionTests: XCTestCase {

    /// 核心回歸：標題讀得到 → 讀不到 → 又讀得到，全程不該有任何 FOCUS。
    func testTitleFlappingToUnknownDoesNotEmitFocus() {
        var tracker = FocusChangeTracker()
        _ = tracker.event(app: "系統設定", window: "")                  // 進場（AX 還沒好）→ SWITCH
        XCTAssertNil(tracker.event(app: "系統設定", window: "隱私權與安全性"),
                     "未知 → 已知只是補上資訊，不是換視窗")
        XCTAssertNil(tracker.event(app: "系統設定", window: ""),
                     "已知 → 未知是讀不到，不是換視窗")
        XCTAssertNil(tracker.event(app: "系統設定", window: "隱私權與安全性"),
                     "讀回同一個視窗，更不該有事件")
    }

    /// 未知標題**不可覆蓋**已知身分——覆蓋掉的話，下次標題讀回來又會被判成換視窗。
    func testUnknownTitleDoesNotOverwriteKnownIdentity() {
        var tracker = FocusChangeTracker()
        _ = tracker.event(app: "Xcode", window: "A.swift")
        _ = tracker.event(app: "Xcode", window: "")                     // 讀不到，身分應維持 A.swift
        XCTAssertNil(tracker.event(app: "Xcode", window: "A.swift"))
        XCTAssertEqual(tracker.event(app: "Xcode", window: "B.swift"),
                       .focus(app: "Xcode", window: "B.swift"),
                       "真的換視窗仍要記")
    }

    /// 空白字元也算讀不到（有些 app 回一個空格）。
    func testWhitespaceOnlyTitleCountsAsUnknown() {
        XCTAssertTrue(FocusChangeTracker.isUnknownTitle(""))
        XCTAssertTrue(FocusChangeTracker.isUnknownTitle("   "))
        XCTAssertTrue(FocusChangeTracker.isUnknownTitle("\n"))
        XCTAssertFalse(FocusChangeTracker.isUnknownTitle("A.swift"))
    }

    /// 「標題只剩易變樣式」跟「讀不到標題」是兩件事，不可混為一談。
    /// `windowIdentity("• ")` 會退回原值 "• "，那仍然是**已知**的標題。
    func testFullyStrippedTitleIsStillKnown() {
        XCTAssertFalse(FocusChangeTracker.isUnknownTitle("• "))
    }

    // MARK: - 換 app 時的基準重設

    /// 換 app 且新 app 讀不到標題時，舊 app 的身分不可留著當基準——
    /// 否則新 app 的標題一讀回來就被判成「換視窗」，SWITCH 後面跟一筆假 FOCUS。
    func testAppSwitchWithUnknownTitleResetsBaseline() {
        var tracker = FocusChangeTracker()
        _ = tracker.event(app: "Xcode", window: "A.swift")
        XCTAssertEqual(tracker.event(app: "AnyDesk", window: ""),
                       .switchApp(app: "AnyDesk", window: ""))
        XCTAssertNil(tracker.event(app: "AnyDesk", window: "新增連線"),
                     "SWITCH 之後才讀到標題，不該再補一筆 FOCUS")
    }

    /// 對照組：換 app 時讀得到標題，之後同 app 內真的換視窗仍要記。
    func testAppSwitchWithKnownTitleStillTracksLaterChanges() {
        var tracker = FocusChangeTracker()
        _ = tracker.event(app: "Xcode", window: "A.swift")
        _ = tracker.event(app: "AnyDesk", window: "新增連線")
        XCTAssertEqual(tracker.event(app: "AnyDesk", window: "遠端桌面"),
                       .focus(app: "AnyDesk", window: "遠端桌面"))
    }

    /// 換 app 本身**不受標題影響**：讀不到標題也照樣是 SWITCH。
    /// （app 名稱來自 NSWorkspace，跟 AX 標題是兩條獨立來源。）
    func testAppSwitchAlwaysEmittedEvenWithUnknownTitles() {
        var tracker = FocusChangeTracker()
        _ = tracker.event(app: "A", window: "")
        XCTAssertEqual(tracker.event(app: "B", window: ""), .switchApp(app: "B", window: ""))
        XCTAssertEqual(tracker.event(app: "A", window: ""), .switchApp(app: "A", window: ""))
    }

    /// 真機序列重演：整段只該留 3 筆 SWITCH，一筆 FOCUS 都不該有。
    func testRealMachineSequenceEmitsOnlySwitches() {
        var tracker = FocusChangeTracker()
        let observations = [
            ("CoPartner", ""),
            ("系統設定", ""),
            ("系統設定", "隱私權與安全性"),
            ("系統設定", ""),
            ("AnyDesk", "新增連線"),
            ("AnyDesk", ""),
            ("AnyDesk", "新增連線"),
        ]
        var focusCount = 0
        var switchCount = 0
        for (app, window) in observations {
            switch tracker.event(app: app, window: window) {
            case .some(.focus): focusCount += 1
            case .some(.switchApp): switchCount += 1
            default: break
            }
        }
        XCTAssertEqual(switchCount, 3)
        XCTAssertEqual(focusCount, 0, "整段沒有真的換視窗，不該有任何 FOCUS")
    }
}
