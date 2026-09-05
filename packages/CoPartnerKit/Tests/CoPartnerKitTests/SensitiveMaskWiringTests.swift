import XCTest
import CoreGraphics
import CaptureEngine
import ScriptNarrator

/// 敏感遮罩的**接線**規則（step 58）。
///
/// `SensitiveTileMask` 的純值行為在 `SensitiveTileMaskTests` 已經測過。這一組測的是
/// 接線那一層的兩個決定——它們在 app 端是 `@MainActor` 的膠水，CI 跑不到，
/// 所以把規則本身用純值重演一次：
///
/// 1. **什麼算敏感**（目前只認系統自己標記的密碼欄，不猜）
/// 2. **讀不到焦點時不清空遮罩**（sticky 的意義就在這裡）
///
/// 為什麼值得測：這一層在 step 58 之前**從來沒有被建立過**——純值層與三個出口
/// 都寫好也測過，但沒有人餵它 region，`isMasked` 永遠是 false。
/// 程式碼看起來有三層保護，實際上那一層從未執行。
final class SensitiveMaskWiringTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_756_800_000)
    private let grid = TileGrid(width: 1600, height: 1000, tileSize: 100)   // 16×10

    // MARK: - 什麼算敏感

    /// 密碼欄是唯一一種**系統自己標記出來、不需要猜**的敏感輸入。
    func testSecureTextFieldIsRecognised() {
        XCTAssertTrue(InputEventTranslator.isSecure(role: "AXTextField",
                                                    subrole: "AXSecureTextField"))
    }

    /// 一般欄位不算——把所有輸入都當敏感等於整片遮掉，那會讓截圖完全沒有用，
    /// 而「沒有用的保護」最後一定會被關掉。
    func testOrdinaryFieldsAreNotSensitive() {
        XCTAssertFalse(InputEventTranslator.isSecure(role: "AXTextField", subrole: nil))
        XCTAssertFalse(InputEventTranslator.isSecure(role: "AXTextArea", subrole: nil))
        XCTAssertFalse(InputEventTranslator.isSecure(role: nil, subrole: nil))
    }

    // MARK: - 遮罩真的會蓋住那個欄位

    /// 密碼欄的 frame → 覆蓋到的每一個 tile 都要被遮。
    /// 少遮一格的後果是密碼框的一角出現在截圖上。
    func testSecureFieldFrameMasksEveryOverlappingTile() {
        var mask = SensitiveTileMask(grid: grid)
        let frame = CGRect(x: 250, y: 150, width: 300, height: 120)   // 跨 x=2…8, y=1…2
        mask.update(regions: [SensitiveRegion(rect: frame, reason: .secureField)], at: t0)

        for tile in grid.tiles(overlapping: frame) {
            XCTAssertTrue(mask.isMasked(tile, at: t0), "tile (\(tile.x),\(tile.y)) 應被遮")
        }
        XCTAssertFalse(mask.isMasked(TileXY(x: 0, y: 0), at: t0), "沒被覆蓋的不該遮")
    }

    // MARK: - 讀不到焦點 ≠ 密碼欄消失

    /// 🔑 **sticky 的意義**：AX 這一瞬間讀不到東西，與密碼欄真的不見了，是兩件事。
    /// 把前者當後者就是**提早解除遮罩**——而解除的那一瞬間剛好被截圖抓到，
    /// 密碼框就出境了。
    func testMaskSurvivesAMomentaryFocusDropout() {
        var mask = SensitiveTileMask(grid: grid, stickySeconds: 5)
        let frame = CGRect(x: 100, y: 100, width: 200, height: 100)
        mask.update(regions: [SensitiveRegion(rect: frame, reason: .secureField)], at: t0)
        let masked = grid.tiles(overlapping: frame)

        // 下一次輪詢讀不到焦點（傳空 region）——遮罩不可以立刻消失。
        mask.update(regions: [], at: t0.addingTimeInterval(0.2))
        for tile in masked {
            XCTAssertTrue(mask.isMasked(tile, at: t0.addingTimeInterval(0.2)),
                          "讀不到焦點的那一瞬間不可以解除遮罩")
        }
        // 但持續消失夠久之後要回收，否則遮罩只會愈積愈多。
        XCTAssertTrue(mask.maskedTiles(at: t0.addingTimeInterval(30)).isEmpty,
                      "sticky 過後要回收，否則整片畫面遲早都被遮掉")
    }

    // MARK: - 接上出境決策

    /// 密碼欄出現時，截圖出境決策要拿得到**非空**的塗黑矩形。
    /// 這條是整條線的端到端：AX → region → tile → 正規化矩形 → 出境決策。
    func testMaskedSecureFieldProducesRedactionRects() {
        var mask = SensitiveTileMask(grid: grid)
        mask.update(regions: [SensitiveRegion(rect: CGRect(x: 100, y: 100, width: 200, height: 100),
                                              reason: .secureField)], at: t0)
        let tiles = mask.maskedTiles(at: t0)
        XCTAssertFalse(tiles.isEmpty)

        let rects = ScreenshotRedaction.normalizedRects(for: tiles, in: grid)
        XCTAssertEqual(rects.count, tiles.count)
        for r in rects {
            XCTAssertTrue((0...1).contains(r.minX) && (0...1).contains(r.minY), "\(r)")
            XCTAssertTrue(r.maxX <= 1.0001 && r.maxY <= 1.0001, "\(r)")
        }
        // 佔比很小 → 出境決策應該放行並帶著矩形，而不是整張不送。
        let fraction = ScreenshotRedaction.maskedFraction(for: tiles, in: grid)
        XCTAssertLessThan(fraction, 0.25)
    }
}
