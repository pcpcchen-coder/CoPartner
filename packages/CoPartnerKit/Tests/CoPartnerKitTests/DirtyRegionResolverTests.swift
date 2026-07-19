import XCTest
import CoreGraphics
import CaptureEngine

/// SCK dirtyRects × Metal hash 融合（§B.1 / ADR-0003）。真擷取行為於 step 18 真機驗。
final class DirtyRegionResolverTests: XCTestCase {
    private let grid = TileGrid(width: 256, height: 256, tileSize: 128)   // 2×2＝4 tiles
    private var resolver: DirtyRegionResolver { DirtyRegionResolver(grid: grid) }

    private struct Info: FrameInfoProviding {
        var status: FrameStatus = .complete
        var dirtyRects: [CGRect] = []
        var contentRect: CGRect = CGRect(x: 0, y: 0, width: 256, height: 256)
    }

    /// 4 個 tile 的 hash，指定 index 翻 8 bit（→ large 變動）。index = y*2 + x。
    private func hashes(changedAt indices: Set<Int> = []) -> (old: [UInt64], new: [UInt64]) {
        let old: [UInt64] = [10, 20, 30, 40]
        var new = old
        for i in indices { new[i] ^= 0xFF }
        return (old, new)
    }

    func testDirtyRectsMapToCorrectTiles() {
        let tiles = resolver.tiles(forDirtyRects: [CGRect(x: 130, y: 10, width: 20, height: 20)])
        XCTAssertEqual(tiles, [TileXY(x: 1, y: 0)])
    }

    func testMultipleRectsAggregate() {
        let tiles = resolver.tiles(forDirtyRects: [
            CGRect(x: 10, y: 10, width: 20, height: 20),     // → (0,0)
            CGRect(x: 130, y: 200, width: 20, height: 20),   // → (1,1)
        ])
        XCTAssertEqual(tiles, [TileXY(x: 0, y: 0), TileXY(x: 1, y: 1)])
    }

    func testOutOfBoundsDirtyRectClampsToGrid() {
        let tiles = resolver.tiles(forDirtyRects: [CGRect(x: 9000, y: 9000, width: 50, height: 50)])
        for t in tiles {
            XCTAssertTrue((0..<grid.cols).contains(t.x), "col \(t.x) 越界")
            XCTAssertTrue((0..<grid.rows).contains(t.y), "row \(t.y) 越界")
        }
    }

    func testEmptyRectsUnchangedHashesReportsNoChange() {
        let h = hashes()
        XCTAssertTrue(resolver.resolve(Info(), oldHashes: h.old, newHashes: h.new).isEmpty)
    }

    func testEmptyRectsButHashChangedStillReportsChange() {
        let h = hashes(changedAt: [3])   // tile (1,1)
        XCTAssertEqual(resolver.resolve(Info(), oldHashes: h.old, newHashes: h.new), [TileXY(x: 1, y: 1)])
    }

    func testIdleStatusFallsBackToHashDiff() {
        // §B.1：status=.idle 常被誤報，不能用來抑制——hash 有變就得報。
        let h = hashes(changedAt: [0])
        XCTAssertEqual(resolver.resolve(Info(status: .idle), oldHashes: h.old, newHashes: h.new),
                       [TileXY(x: 0, y: 0)])
    }

    func testRectsAndHashUnioned() {
        let h = hashes(changedAt: [0])   // hash 側 (0,0)
        let info = Info(dirtyRects: [CGRect(x: 130, y: 10, width: 10, height: 10)])  // rect 側 (1,0)
        XCTAssertEqual(resolver.resolve(info, oldHashes: h.old, newHashes: h.new),
                       [TileXY(x: 0, y: 0), TileXY(x: 1, y: 0)])
    }

    func testHashLengthMismatchIgnored() {
        // 只給 2 個 hash（需 4）→ 視為無有效比較，回空。
        XCTAssertTrue(resolver.hashChangedTiles(oldHashes: [1, 2], newHashes: [3, 4]).isEmpty)
    }
}
