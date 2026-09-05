import XCTest
import CoreGraphics
import CoPartnerCore
import CaptureEngine
@testable import CloudRouter

/// 截圖出境（step 58）。
///
/// 這一組守的是整個專案隱私上最大的一步：**開始把螢幕畫面送到雲端**。
/// 圖比文字保守，理由是圖沒辦法事後查——文字送錯了還看得出來送了什麼；
/// 一張截圖出去之後，上面有什麼只有收到的人知道。
final class ScreenshotEgressTests: XCTestCase {

    // MARK: - 幾何（CaptureEngine 那一半）

    private let grid = TileGrid(width: 800, height: 600, tileSize: 100)   // 8×6 = 48 tiles

    /// 正規化而不是像素：送出去的圖幾乎一定被縮放過，而縮放比例在那一層是未知的。
    func testRectsAreNormalisedToZeroOne() throws {
        let rects = ScreenshotRedaction.normalizedRects(for: [TileXY(x: 0, y: 0)], in: grid)
        XCTAssertEqual(rects.count, 1)
        let r = try XCTUnwrap(rects.first)
        XCTAssertEqual(r.minX, 0, accuracy: 0.0001)
        XCTAssertEqual(r.minY, 0, accuracy: 0.0001)
        XCTAssertEqual(r.width, 100.0 / 800, accuracy: 0.0001)
        XCTAssertEqual(r.height, 100.0 / 600, accuracy: 0.0001)
    }

    /// 右下角那一格要落在右下角——y 向下、原點左上，與影像座標同向。
    /// 翻轉錯的話會塗到鏡像的位置，而**該遮的地方沒被遮**，畫面上還看不出來。
    func testBottomRightTileMapsToBottomRight() throws {
        let rects = ScreenshotRedaction.normalizedRects(for: [TileXY(x: 7, y: 5)], in: grid)
        let r = try XCTUnwrap(rects.first)
        XCTAssertEqual(r.minX, 700.0 / 800, accuracy: 0.0001)
        XCTAssertEqual(r.minY, 500.0 / 600, accuracy: 0.0001)
        XCTAssertEqual(r.maxX, 1.0, accuracy: 0.0001)
        XCTAssertEqual(r.maxY, 1.0, accuracy: 0.0001)
    }

    /// 輸出順序要穩定——`Set` 的順序不穩定會讓測試與 diff 都沒辦法讀。
    func testOutputOrderIsStable() {
        let tiles: Set<TileXY> = [TileXY(x: 3, y: 1), TileXY(x: 0, y: 0), TileXY(x: 1, y: 1)]
        let a = ScreenshotRedaction.normalizedRects(for: tiles, in: grid)
        let b = ScreenshotRedaction.normalizedRects(for: tiles, in: grid)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.first?.minY, 0, "先列 y 小的")
    }

    /// **格線退化時比例回 1，不是 0。** 算不出來就當成「整片敏感」，
    /// 讓下游的上限規則自動擋掉。回 0 會讓退化的格線看起來像「完全乾淨」，
    /// 那是最糟的預設值。
    func testDegenerateGridCountsAsFullyMasked() {
        XCTAssertEqual(ScreenshotRedaction.maskedFraction(for: [], in: TileGrid(width: 0, height: 0)), 1)
        XCTAssertTrue(ScreenshotRedaction.normalizedRects(for: [TileXY(x: 0, y: 0)],
                                                         in: TileGrid(width: 0, height: 0)).isEmpty)
    }

    func testMaskedFractionCountsTiles() {
        let tiles = Set((0..<12).map { TileXY(x: $0 % 8, y: $0 / 8) })   // 12 / 48
        XCTAssertEqual(ScreenshotRedaction.maskedFraction(for: tiles, in: grid), 0.25, accuracy: 0.0001)
    }

    // MARK: - 政策（CloudRouter 那一半）

    private func decide(blacklisted: Bool = false, fraction: Double = 0,
                        rects: [CGRect] = []) -> ScreenshotEgressPolicy.Decision {
        ScreenshotEgressPolicy.decide(isBlacklistedApp: blacklisted, frontmostAppName: "測試 app",
                                      maskedFraction: fraction, redactRects: rects)
    }

    /// **黑名單 app 沒有「遮一遮就可以送」這個選項。** 密碼管理器、銀行頁面 → 整張不送。
    func testBlacklistedAppWithholdsEntirely() {
        guard case .withhold(let reason) = decide(blacklisted: true, fraction: 0) else {
            return XCTFail("黑名單 app 必須整張不送")
        }
        XCTAssertTrue(reason.contains("黑名單"), reason)
    }

    /// 敏感面積過大 → 整張不送。tile 遮罩是保守偵測，它大面積命中代表這個畫面
    /// 就是不該離開這台機器。
    func testTooMuchMaskedWithholds() {
        guard case .send = decide(fraction: 0.25) else { return XCTFail("剛好在上限應放行") }
        guard case .withhold(let reason) = decide(fraction: 0.26) else {
            return XCTFail("超過上限必須不送")
        }
        XCTAssertTrue(reason.contains("26%"), reason)
    }

    /// 算不出比例（NaN）→ 不送。呼叫端可能傳進奇怪的值，這裡自己也守一次。
    func testNonFiniteFractionWithholds() {
        guard case .withhold = decide(fraction: .nan) else { return XCTFail("NaN 必須不送") }
        guard case .withhold = decide(fraction: -1) else { return XCTFail("負值必須不送") }
    }

    /// 乾淨畫面 → 放行，並把要塗黑的矩形帶出去。
    func testCleanScreenSendsWithRects() {
        let rects = [CGRect(x: 0, y: 0, width: 0.1, height: 0.1)]
        guard case .send(let out) = decide(fraction: 0.02, rects: rects) else {
            return XCTFail("乾淨畫面應放行")
        }
        XCTAssertEqual(out, rects)
    }

    // MARK: - 閘門：沒有決定就沒有圖

    private func envelope(withImage image: String?) -> ContextEnvelope {
        EnvelopeBuilder().build(now: Date(), steps: [], sessionSummary: "s", openLoop: "o",
                                focusSnapshotJPEGBase64: image)
    }

    private var gate: EgressGate {
        EgressGate(scrubber: PassThroughScrubber(), piplDetector: { _ in false })
    }

    /// 🔑 **這條是這一整段存在的理由。**
    ///
    /// 在 step 58 之前，`EgressGate` 完全沒有看過 `focusSnapshotJPEGBase64`——
    /// 只掃文字，然後 `var out = envelope` 把圖原封不動帶出去。塞一張圖進去
    /// 就會一路出境而不經任何檢查，**連 PIPL 硬牆都繞過**（硬牆掃的是文字）。
    ///
    /// 修法不是「加一段掃圖的邏輯」——圖沒辦法掃。改成結構上不可能漏：
    /// 沒有人明確決定要送，圖就在這裡被拿掉。
    func testImageIsStrippedWhenNobodyDecided() {
        guard case .allow(let out) = gate.check(envelope(withImage: "BASE64")) else {
            return XCTFail("其餘欄位應照常出境")
        }
        XCTAssertNil(out.focusSnapshotJPEGBase64, "沒有決定 → 圖必須被拿掉")
    }

    func testImageSurvivesAnExplicitSendDecision() {
        guard case .allow(let out) = gate.check(envelope(withImage: "BASE64"),
                                                screenshot: .send(redact: [])) else {
            return XCTFail("應放行")
        }
        XCTAssertEqual(out.focusSnapshotJPEGBase64, "BASE64")
    }

    func testWithholdDecisionAlsoStripsIt() {
        guard case .allow(let out) = gate.check(envelope(withImage: "BASE64"),
                                                screenshot: .withhold(reason: "黑名單")) else {
            return XCTFail("其餘欄位應照常出境")
        }
        XCTAssertNil(out.focusSnapshotJPEGBase64)
    }

    /// PIPL 命中時整包拒出，圖當然也不會出去——**即使有明確的 send 決定**。
    /// 硬牆在圖片決定之前，順序不可以顛倒。
    func testPIPLBlocksEverythingIncludingAnApprovedImage() {
        let blocking = EgressGate(scrubber: PassThroughScrubber(), piplDetector: { _ in true })
        guard case .blocked = blocking.check(envelope(withImage: "BASE64"),
                                             screenshot: .send(redact: [])) else {
            return XCTFail("PIPL 命中必須整包拒出，send 決定不能蓋過硬牆")
        }
    }
}

private struct PassThroughScrubber: PIIScrubbing {
    func scrub(_ text: String) -> (clean: String, foundPII: Bool) { (text, false) }
}
