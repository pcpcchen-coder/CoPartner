import XCTest
import CoreGraphics
import CaptureEngine

/// Tile 幾何換算（§B.2）。純數學、零平台依賴。
final class TileGridTests: XCTestCase {
    private let grid = TileGrid(width: 1920, height: 1080, tileSize: 128)

    func testColsRowsCeil() {
        XCTAssertEqual(grid.cols, 15)   // ceil(1920/128)=15
        XCTAssertEqual(grid.rows, 9)    // ceil(1080/128)=8.4→9
    }

    func testTileIndexAtOrigin() {
        XCTAssertEqual(grid.tileIndex(for: CGPoint(x: 0, y: 0)), TileXY(x: 0, y: 0))
    }

    func testTileIndexMidTile() {
        XCTAssertEqual(grid.tileIndex(for: CGPoint(x: 200, y: 100)), TileXY(x: 1, y: 0))
    }

    func testTileIndexAtExactBoundary() {
        // 邊界像素屬於「下一格」
        XCTAssertEqual(grid.tileIndex(for: CGPoint(x: 128, y: 256)), TileXY(x: 1, y: 2))
    }

    func testTileIndexClampsNegativeAndOverflow() {
        XCTAssertEqual(grid.tileIndex(for: CGPoint(x: -50, y: -50)), TileXY(x: 0, y: 0))
        XCTAssertEqual(grid.tileIndex(for: CGPoint(x: 9999, y: 9999)), TileXY(x: 14, y: 8))
    }

    func testTilesOverlappingRectSpanningMultipleTiles() {
        let tiles = grid.tiles(overlapping: CGRect(x: 100, y: 100, width: 200, height: 100))
        // x:[100,300) → 欄 0,1,2；y:[100,200) → 列 0,1
        XCTAssertEqual(Set(tiles), Set([
            TileXY(x: 0, y: 0), TileXY(x: 1, y: 0), TileXY(x: 2, y: 0),
            TileXY(x: 0, y: 1), TileXY(x: 1, y: 1), TileXY(x: 2, y: 1),
        ]))
    }

    func testTilesOverlappingRectSingleTile() {
        // rect [0,128)×[0,128) 只碰 tile (0,0)（右緣 128 不算進下一格）
        XCTAssertEqual(grid.tiles(overlapping: CGRect(x: 0, y: 0, width: 128, height: 128)), [TileXY(x: 0, y: 0)])
    }

    func testTilesOverlappingRectClampsToGridBounds() {
        let tiles = grid.tiles(overlapping: CGRect(x: 1900, y: 1060, width: 500, height: 500))
        XCTAssertFalse(tiles.isEmpty)
        for t in tiles {
            XCTAssertTrue((0..<grid.cols).contains(t.x), "col \(t.x) 越界")
            XCTAssertTrue((0..<grid.rows).contains(t.y), "row \(t.y) 越界")
        }
        XCTAssertTrue(tiles.contains(TileXY(x: 14, y: 8)))   // 右下角 tile
    }

    func testRectForTile() {
        XCTAssertEqual(grid.rect(forTileX: 1, y: 2), CGRect(x: 128, y: 256, width: 128, height: 128))
    }

    func testRectForEdgeTileClampsToScreen() {
        // 最後一列 y=8：oy=1024，高度只剩 1080-1024=56
        XCTAssertEqual(grid.rect(forTileX: 0, y: 8), CGRect(x: 0, y: 1024, width: 128, height: 56))
    }

    func testRectForTileRoundTrip() {
        for xy in [TileXY(x: 0, y: 0), TileXY(x: 5, y: 3), TileXY(x: 14, y: 8)] {
            let r = grid.rect(forTileX: xy.x, y: xy.y)
            XCTAssertEqual(grid.tileIndex(for: r.origin), xy)
        }
    }
}
