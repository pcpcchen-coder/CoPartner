import XCTest
import CoPartnerCore
@testable import ActionExecutor

/// UI 動作閘門（step 53.6-B）。
///
/// UI 動作不經 shell 沙箱，沒有 sbpl 兜底，所以這一層是**唯一**的結構性防線。
/// 它守的性質只有一句：**做不到的時候要大聲說做不到。**
final class UIActionGateTests: XCTestCase {

    private func decide(_ kind: ProposedAction.Kind,
                        trusted: Bool = true, canPerform: Bool = true) -> UIActionGate.Decision {
        UIActionGate.decide(kind: kind, accessibilityTrusted: trusted, canPerform: canPerform)
    }

    // MARK: - 這是不是 UI 動作

    func testUIKindsAreRecognised() {
        for kind: ProposedAction.Kind in [.screenshot, .click(x: 1, y: 2), .typeText("hi"),
                                          .keypress("cmd+c"), .scroll(x: 1, y: 2, dx: 0, dy: 3)] {
            XCTAssertTrue(UIActionGate.isUIAction(kind), kind.summary)
        }
    }

    func testNonUIKindsAreNot() {
        for kind: ProposedAction.Kind in [.shell(argv: ["/bin/ls"]), .readFile(path: "/tmp/a"),
                                          .writeFile(path: "/tmp/a", contents: ""),
                                          .outboundComms(kind: "email", target: "a@b.c")] {
            XCTAssertFalse(UIActionGate.isUIAction(kind), kind.summary)
            guard case .refuse = decide(kind) else {
                return XCTFail("\(kind.summary) 不該走 UI 路徑")
            }
        }
    }

    // MARK: - 硬規則

    /// **沒有輔助使用權限一定拒絕。** 沒有它時 `CGEvent.post` 不會失敗、不會丟錯，
    /// 就是靜默地什麼都不做——整條鏈會顯示「已執行」而畫面上什麼都沒發生。
    func testNoAccessibilityAlwaysRefuses() {
        for kind: ProposedAction.Kind in [.click(x: 1, y: 2), .typeText("hi"),
                                          .keypress("cmd+c"), .scroll(x: 1, y: 2, dx: 0, dy: 3)] {
            guard case .refuse(let reason) = decide(kind, trusted: false) else {
                return XCTFail("\(kind.summary) 在沒有權限時必須拒絕")
            }
            XCTAssertTrue(reason.contains("輔助使用"), reason)
        }
    }

    /// 權限與能力旗標**兩個都要**。任一為 false 就拒絕。
    func testBothPermissionAndCapabilityAreRequired() {
        XCTAssertEqual(decide(.click(x: 1, y: 1), trusted: true, canPerform: true), .perform)
        for (trusted, canPerform) in [(true, false), (false, true), (false, false)] {
            guard case .refuse = decide(.click(x: 1, y: 1), trusted: trusted, canPerform: canPerform) else {
                return XCTFail("trusted=\(trusted) canPerform=\(canPerform) 應拒絕")
            }
        }
    }

    /// 權限的檢查要**排在能力旗標之前**：翻開能力之前就該看得到「權限沒給」這件事，
    /// 否則第一次啟用時會被兩個原因同時擋住，而訊息只講得出其中一個。
    func testMissingPermissionIsReportedEvenWhenCapabilityIsOff() {
        guard case .refuse(let reason) = decide(.click(x: 1, y: 1),
                                                trusted: false, canPerform: false) else {
            return XCTFail("應拒絕")
        }
        XCTAssertTrue(reason.contains("輔助使用"), "兩個都缺時要先講權限：\(reason)")
    }

    /// **截圖刻意不支援。** 它是給模型看的，該由擷取管線產生並經出境閘門
    /// （PII 遮罩 + PIPL 硬牆）。在這裡偷截一張＝靜默拿掉整個出境設計。
    func testScreenshotIsRefusedEvenWithEverythingEnabled() {
        guard case .refuse(let reason) = decide(.screenshot) else {
            return XCTFail("截圖不該從 UI 執行端走")
        }
        XCTAssertTrue(reason.contains("出境"), reason)
    }
}
