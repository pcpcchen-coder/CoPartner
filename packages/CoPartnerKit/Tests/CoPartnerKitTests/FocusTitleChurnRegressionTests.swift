import XCTest
import ScriptNarrator

/// step 53 dogfood 真機回歸：**視窗標題本身會變**，不可直接當視窗身分。
///
/// 真機症狀：拉終端機視窗大小時，標題裡的尺寸跟著變
/// （"CoPartner — -zsh — 104×33" → "105×33" → "107×33" …），
/// FocusChangeTracker 每次都判定「換視窗」→ 0.1 秒內噴 6 行 FOCUS 淹沒劇本，
/// 而且那串噪音會餵進 L1，讓模型把「拉視窗」腦補成「調整終端機連線參數」。
///
/// 這是 M2 那次（誤用 AX value 當識別）的**同類錯誤、不同成因**：
/// 前者是拿內容當身分，後者是拿會變的標題當身分。
final class FocusTitleChurnRegressionTests: XCTestCase {

    /// 核心回歸：拉視窗大小不該產生任何 FOCUS。
    func testTerminalResizeDoesNotEmitFocus() {
        var tracker = FocusChangeTracker()
        _ = tracker.event(app: "終端機", window: "CoPartner — -zsh — 99×33")   // 首次進場 → SWITCH

        // 真機實測擷取的序列（0.1 秒內 6 次）。
        for title in ["CoPartner — -zsh — 104×33", "CoPartner — -zsh — 105×33",
                      "CoPartner — -zsh — 106×33", "CoPartner — -zsh — 107×33",
                      "CoPartner — -zsh — 109×33", "CoPartner — -zsh — 110×33"] {
            XCTAssertNil(tracker.event(app: "終端機", window: title),
                         "只是標題裡的尺寸在變，不是換視窗：\(title)")
        }
    }

    /// 同一個終端機視窗換了工作目錄 / 指令 → 標題的**非尺寸**部分變了，這才是真的該記。
    func testTerminalRealTitleChangeStillEmitsFocus() {
        var tracker = FocusChangeTracker()
        _ = tracker.event(app: "終端機", window: "CoPartner — -zsh — 99×33")
        let event = tracker.event(app: "終端機", window: "sidecar — -zsh — 99×33")
        XCTAssertEqual(event, .focus(app: "終端機", window: "sidecar — -zsh — 99×33"),
                       "尺寸以外的部分變了，是真的換了視窗/工作目錄")
    }

    // MARK: - 正規化的個別樣式

    func testStripsTerminalDimensions() {
        let variants = ["A — 110×33", "A — 110x33", "A - 110×33", "A – 110×33", "A—110×33"]
        for v in variants {
            XCTAssertEqual(FocusChangeTracker.windowIdentity(v), "A", "未剝乾淨：\(v)")
        }
    }

    func testStripsLeadingUnreadCountAndProgress() {
        XCTAssertEqual(FocusChangeTracker.windowIdentity("(3) Inbox"), "Inbox")
        XCTAssertEqual(FocusChangeTracker.windowIdentity("(45%) Downloading"), "Downloading")
    }

    func testStripsEditorDirtyMarker() {
        XCTAssertEqual(FocusChangeTracker.windowIdentity("• main.swift"), "main.swift")
        XCTAssertEqual(FocusChangeTracker.windowIdentity("main.swift •"), "main.swift")
    }

    // MARK: - 保守偏留：剝過頭比留噪音更糟

    /// 只是「像」尺寸的正常標題不可被剝掉——漏記 FOCUS 是看不見的傷害。
    func testDoesNotStripLegitimateTitleContent() {
        // 尺寸樣式只在字串**結尾**才剝，中間出現的維持原樣。
        XCTAssertEqual(FocusChangeTracker.windowIdentity("報表 1920×1080 規格.pdf"),
                       "報表 1920×1080 規格.pdf")
        // 純數字不帶 × 的不動。
        XCTAssertEqual(FocusChangeTracker.windowIdentity("Chapter 12"), "Chapter 12")
    }

    /// 極端情況：整個標題都被樣式吃掉時退回原值，不可回空字串——
    /// 空字串會讓所有這類視窗被當成同一個。
    func testFullyStrippedTitleFallsBackToOriginal() {
        XCTAssertEqual(FocusChangeTracker.windowIdentity("• "), "• ")
    }

    /// 不同視窗的身分必須仍然不同（正規化不可把它們混成一個）。
    func testDistinctWindowsRemainDistinctAfterNormalization() {
        let a = FocusChangeTracker.windowIdentity("AppCoordinator.swift — 100×40")
        let b = FocusChangeTracker.windowIdentity("MenuBarContentView.swift — 100×40")
        XCTAssertNotEqual(a, b)
    }
}
