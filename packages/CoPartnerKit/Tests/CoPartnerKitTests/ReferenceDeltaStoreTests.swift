import XCTest
import CaptureEngine

/// reference+delta 重建（§B.7）：以不透明 hash 代表 tile 內容，驗重建簿記與損毀防禦。
final class ReferenceDeltaStoreTests: XCTestCase {
    private let grid = TileGrid(width: 256, height: 256, tileSize: 128)   // 2×2 = 4 tiles

    private func cell(_ h: UInt64) -> TileCell { TileCell(hash: h) }

    private func refSnapshot() -> FrameSnapshot {
        FrameSnapshot(grid: grid, tiles: [
            TileXY(x: 0, y: 0): cell(1),
            TileXY(x: 1, y: 0): cell(2),
            TileXY(x: 0, y: 1): cell(3),
            TileXY(x: 1, y: 1): cell(4),
        ])
    }

    func testReconstructNoDeltasEqualsReference() {
        var store = ReferenceDeltaStore()
        let ref = refSnapshot()
        store.setReference(ref)
        XCTAssertEqual(store.reconstruct(), ref)
    }

    func testSingleDeltaOverwritesTile() throws {
        var store = ReferenceDeltaStore()
        store.setReference(refSnapshot())
        try store.appendDelta(DeltaFrame(grid: grid, changed: [TileXY(x: 0, y: 0): cell(99)]))
        let out = store.reconstruct()
        XCTAssertEqual(out.tiles[TileXY(x: 0, y: 0)], cell(99))
        XCTAssertEqual(out.tiles[TileXY(x: 1, y: 1)], cell(4))   // 其餘不變
    }

    func testLaterDeltaWinsSameTile() throws {
        var store = ReferenceDeltaStore()
        store.setReference(refSnapshot())
        try store.appendDelta(DeltaFrame(grid: grid, changed: [TileXY(x: 0, y: 0): cell(10)]))
        try store.appendDelta(DeltaFrame(grid: grid, changed: [TileXY(x: 0, y: 0): cell(20)]))
        XCTAssertEqual(store.reconstruct().tiles[TileXY(x: 0, y: 0)], cell(20))   // 後寫覆蓋
    }

    func testDeltaAddsPreviouslyBlankTile() throws {
        var store = ReferenceDeltaStore()
        store.setReference(FrameSnapshot(grid: grid, tiles: [TileXY(x: 0, y: 0): cell(1)]))
        try store.appendDelta(DeltaFrame(grid: grid, changed: [TileXY(x: 1, y: 1): cell(7)]))
        XCTAssertEqual(store.reconstruct().tiles[TileXY(x: 1, y: 1)], cell(7))
    }

    func testReconstructThroughIntermediateIndex() throws {
        var store = ReferenceDeltaStore()
        store.setReference(refSnapshot())
        try store.appendDelta(DeltaFrame(grid: grid, changed: [TileXY(x: 0, y: 0): cell(11)]))
        try store.appendDelta(DeltaFrame(grid: grid, changed: [TileXY(x: 0, y: 0): cell(22)]))
        XCTAssertEqual(store.reconstruct(throughDeltaIndex: 0).tiles[TileXY(x: 0, y: 0)], cell(11))
    }

    func testPendingCoverageTracksChangedArea() throws {
        var store = ReferenceDeltaStore()
        store.setReference(refSnapshot())
        XCTAssertEqual(store.pendingDeltaCoverage, 0, accuracy: 1e-9)
        try store.appendDelta(DeltaFrame(grid: grid, changed: [TileXY(x: 0, y: 0): cell(11)]))
        XCTAssertEqual(store.pendingDeltaCoverage, 0.25, accuracy: 1e-9)   // 1/4
        try store.appendDelta(DeltaFrame(grid: grid, changed: [TileXY(x: 1, y: 0): cell(12)]))
        XCTAssertEqual(store.pendingDeltaCoverage, 0.5, accuracy: 1e-9)    // 2/4 聯集
        try store.appendDelta(DeltaFrame(grid: grid, changed: [TileXY(x: 0, y: 0): cell(13)]))
        XCTAssertEqual(store.pendingDeltaCoverage, 0.5, accuracy: 1e-9)    // 同 tile 不重複計
    }

    func testGridMismatchDeltaThrows() {
        var store = ReferenceDeltaStore()
        store.setReference(refSnapshot())
        let otherGrid = TileGrid(width: 512, height: 512, tileSize: 128)   // 4×4，與 reference 不符
        XCTAssertThrowsError(try store.appendDelta(DeltaFrame(grid: otherGrid, changed: [:]))) { err in
            XCTAssertEqual(err as? ReferenceDeltaError, .gridMismatch)
        }
    }

    func testAppendWithoutReferenceThrows() {
        var store = ReferenceDeltaStore()
        XCTAssertThrowsError(try store.appendDelta(DeltaFrame(grid: grid, changed: [:]))) { err in
            XCTAssertEqual(err as? ReferenceDeltaError, .noReference)
        }
    }
}
