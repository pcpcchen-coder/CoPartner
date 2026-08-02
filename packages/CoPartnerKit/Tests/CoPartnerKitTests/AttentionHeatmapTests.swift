import XCTest
import CaptureEngine

/// 衰減式注意力熱圖（§C.4 / §G）：加權、指數衰減、TTL 淘汰、topTiles、隱私「只存聚合」不變式。
final class AttentionHeatmapTests: XCTestCase {
    private let grid = TileGrid(width: 256, height: 256, tileSize: 128)   // 2×2
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let tile = TileXY(x: 0, y: 0)

    func testReinforceRaisesWeight() {
        var hm = AttentionHeatmap(grid: grid, halfLife: 20)
        hm.reinforce(tile: tile, weight: 1, at: t0)
        XCTAssertGreaterThan(hm.weight(for: tile), 0)
    }

    func testDecayReducesOverTime() {
        var hm = AttentionHeatmap(grid: grid, halfLife: 10, epsilon: 0.0001)
        hm.reinforce(tile: tile, weight: 1, at: t0)
        let before = hm.weight(for: tile)
        hm.decay(to: t0.addingTimeInterval(10))   // 一個半衰期 → 折半
        XCTAssertEqual(hm.weight(for: tile), before * 0.5, accuracy: 1e-6)
    }

    func testNegligibleWeightEvictedByTTL() {
        var hm = AttentionHeatmap(grid: grid, halfLife: 1, epsilon: 0.01)
        hm.reinforce(tile: tile, weight: 1, at: t0)
        hm.decay(to: t0.addingTimeInterval(100))  // 遠超多個半衰期 → 趨近 0
        XCTAssertEqual(hm.weight(for: tile), 0)
        XCTAssertEqual(hm.storedTileCount, 0)      // TTL 淘汰
    }

    func testTopTilesHottestFirst() {
        var hm = AttentionHeatmap(grid: grid, halfLife: 100, epsilon: 0.0001)
        hm.reinforce(tile: TileXY(x: 0, y: 0), weight: 1, at: t0)
        hm.reinforce(tile: TileXY(x: 1, y: 1), weight: 3, at: t0)
        hm.reinforce(tile: TileXY(x: 1, y: 0), weight: 2, at: t0)
        XCTAssertEqual(hm.topTiles(2), [TileXY(x: 1, y: 1), TileXY(x: 1, y: 0)])
    }

    func testOnlyAggregateStored() {
        var hm = AttentionHeatmap(grid: grid, halfLife: 1000)
        for _ in 0..<1000 { hm.reinforce(tile: tile, weight: 1, at: t0) }   // 同 tile 猛敲
        XCTAssertEqual(hm.storedTileCount, 1)   // 只存 1 筆聚合權重，非 1000 筆事件（隱私不變式）
    }

    func testSummaryNamesHotRegionElseEmpty() {
        var hm = AttentionHeatmap(grid: grid, halfLife: 100)
        XCTAssertEqual(hm.summary(), "")        // 冷 → 空
        hm.reinforce(tile: tile, weight: 5, at: t0)
        XCTAssertFalse(hm.summary().isEmpty)    // 熱 → 有轉述
    }
}
