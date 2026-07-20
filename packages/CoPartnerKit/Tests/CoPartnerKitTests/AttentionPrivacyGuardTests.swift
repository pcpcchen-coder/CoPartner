import XCTest
import CoreGraphics
import CaptureEngine

/// 熱圖隱私串接（§C.4/§G）：遮罩 tile 不 reinforce、summary/topTiles 排除遮罩區。
final class AttentionPrivacyGuardTests: XCTestCase {
    private let grid = TileGrid(width: 256, height: 256, tileSize: 128)   // 2×2
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func maskCovering(_ rect: CGRect) -> SensitiveTileMask {
        var m = SensitiveTileMask(grid: grid, stickySeconds: 100)
        m.update(regions: [SensitiveRegion(rect: rect, reason: .secureField)], at: t0)
        return m
    }
    private let tile00 = CGRect(x: 0, y: 0, width: 100, height: 100)      // → tile (0,0)

    func testMaskedTileNotReinforced() {
        var hm = AttentionHeatmap(grid: grid, halfLife: 100)
        AttentionPrivacyGuard.reinforceIfAllowed(&hm, tile: TileXY(x: 0, y: 0), weight: 5, at: t0,
                                                 mask: maskCovering(tile00))
        XCTAssertEqual(hm.weight(for: TileXY(x: 0, y: 0)), 0)             // 遮罩 → 沒加進去
    }

    func testUnmaskedReinforceNormal() {
        var hm = AttentionHeatmap(grid: grid, halfLife: 100)
        AttentionPrivacyGuard.reinforceIfAllowed(&hm, tile: TileXY(x: 1, y: 1), weight: 5, at: t0,
                                                 mask: maskCovering(tile00))   // 遮 (0,0)，不遮 (1,1)
        XCTAssertGreaterThan(hm.weight(for: TileXY(x: 1, y: 1)), 0)
    }

    func testTopTilesExcludeMasked() {
        var hm = AttentionHeatmap(grid: grid, halfLife: 100)
        hm.reinforce(tile: TileXY(x: 0, y: 0), weight: 3, at: t0)         // 最熱但將被遮
        hm.reinforce(tile: TileXY(x: 1, y: 1), weight: 1, at: t0)
        let visible = AttentionPrivacyGuard.visibleTopTiles(hm, mask: maskCovering(tile00), at: t0, 5)
        XCTAssertEqual(visible, [TileXY(x: 1, y: 1)])                     // (0,0) 被排除
    }

    func testSummaryFallsBackToUnmaskedTile() {
        var hm = AttentionHeatmap(grid: grid, halfLife: 100)
        hm.reinforce(tile: TileXY(x: 0, y: 0), weight: 3, at: t0)         // 遮
        hm.reinforce(tile: TileXY(x: 1, y: 1), weight: 1, at: t0)
        let summary = AttentionPrivacyGuard.sanitizedSummary(hm, mask: maskCovering(tile00), at: t0)
        XCTAssertTrue(summary.contains("(1, 1)"))
        XCTAssertFalse(summary.contains("(0, 0)"))
    }

    func testAllMaskedSummaryEmpty() {
        var hm = AttentionHeatmap(grid: grid, halfLife: 100)
        hm.reinforce(tile: TileXY(x: 0, y: 0), weight: 3, at: t0)
        let fullMask = maskCovering(CGRect(x: 0, y: 0, width: 256, height: 256))   // 全遮
        XCTAssertEqual(AttentionPrivacyGuard.sanitizedSummary(hm, mask: fullMask, at: t0), "")
    }
}
