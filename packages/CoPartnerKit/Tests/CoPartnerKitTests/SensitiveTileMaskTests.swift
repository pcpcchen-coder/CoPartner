import XCTest
import CoreGraphics
import CaptureEngine

/// tile 級遮罩（§G）：region→tile 聯集、sticky fail-closed、三出口單點鎖。
final class SensitiveTileMaskTests: XCTestCase {
    private let grid = TileGrid(width: 256, height: 256, tileSize: 128)   // 2×2
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func region(_ rect: CGRect, _ reason: SensitiveRegion.Reason = .secureField) -> SensitiveRegion {
        SensitiveRegion(rect: rect, reason: reason)
    }

    func testRegionMapsToOverlappingTiles() {
        var mask = SensitiveTileMask(grid: grid)
        mask.update(regions: [region(CGRect(x: 0, y: 0, width: 120, height: 120))], at: t0)
        XCTAssertTrue(mask.isMasked(TileXY(x: 0, y: 0), at: t0))
        XCTAssertFalse(mask.isMasked(TileXY(x: 1, y: 1), at: t0))
    }

    func testMultipleRegionsUnion() {
        var mask = SensitiveTileMask(grid: grid)
        mask.update(regions: [
            region(CGRect(x: 0, y: 0, width: 100, height: 100)),        // (0,0)
            region(CGRect(x: 130, y: 130, width: 100, height: 100)),    // (1,1)
        ], at: t0)
        XCTAssertEqual(mask.maskedTiles(at: t0), [TileXY(x: 0, y: 0), TileXY(x: 1, y: 1)])
    }

    func testStickyKeepsMaskAfterRegionGone() {
        var mask = SensitiveTileMask(grid: grid, stickySeconds: 5)
        mask.update(regions: [region(CGRect(x: 0, y: 0, width: 100, height: 100))], at: t0)
        mask.update(regions: [], at: t0.addingTimeInterval(3))          // region 消失，但仍在 sticky 窗
        XCTAssertTrue(mask.isMasked(TileXY(x: 0, y: 0), at: t0.addingTimeInterval(3)))
    }

    func testStickyExpiresAfterWindow() {
        var mask = SensitiveTileMask(grid: grid, stickySeconds: 5)
        mask.update(regions: [region(CGRect(x: 0, y: 0, width: 100, height: 100))], at: t0)
        XCTAssertFalse(mask.isMasked(TileXY(x: 0, y: 0), at: t0.addingTimeInterval(6)))   // 超窗、自然到期
    }

    // MARK: 三出口單點鎖
    func testMaskedTileSkipsOCRAnyBase() {
        XCTAssertEqual(TileMaskPolicy.effectiveTextSource(masked: true, base: .accessibility), .skip)
        XCTAssertEqual(TileMaskPolicy.effectiveTextSource(masked: true, base: .ocr), .skip)
    }

    func testMaskedTileNeverPersists() {
        XCTAssertFalse(TileMaskPolicy.mayPersist(masked: true))
    }

    func testMaskedTileNeverReinforcesAttention() {
        XCTAssertFalse(TileMaskPolicy.mayReinforceAttention(masked: true))
    }

    func testUnmaskedPassesThrough() {
        XCTAssertEqual(TileMaskPolicy.effectiveTextSource(masked: false, base: .accessibility), .accessibility)
        XCTAssertTrue(TileMaskPolicy.mayPersist(masked: false))
        XCTAssertTrue(TileMaskPolicy.mayReinforceAttention(masked: false))
    }
}
