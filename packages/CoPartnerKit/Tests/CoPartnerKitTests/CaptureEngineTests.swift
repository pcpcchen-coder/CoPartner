import XCTest
import CoreGraphics
import CoPartnerCore
import CaptureEngine

/// CaptureEngine 幀→dirty-tile 事件管線（用假來源；真擷取 🔒 step 18）。
final class CaptureEngineTests: XCTestCase {
    private let grid = TileGrid(width: 256, height: 256, tileSize: 128)   // 2×2＝4 tiles
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)

    /// 依序吐出 canned frames 後結束的假來源。
    private struct FakeProducer: FrameProducer {
        let framesToYield: [TileFrame]
        func frames() -> AsyncStream<TileFrame> {
            AsyncStream { continuation in
                for frame in framesToYield { continuation.yield(frame) }
                continuation.finish()
            }
        }
        func stop() {}
    }

    /// 永不吐、永不結束的來源（測 stop()）。
    private struct NeverEndingProducer: FrameProducer {
        func frames() -> AsyncStream<TileFrame> { AsyncStream { _ in } }
        func stop() {}
    }

    func testEmitsEventForHashChangedTile() async {
        let engine = CaptureEngine(grid: grid)
        let frame1 = TileFrame(hashes: [10, 20, 30, 40], timestamp: t0)                    // baseline
        let frame2 = TileFrame(hashes: [10, 20, 30, 40 ^ 0xFF], timestamp: t0.addingTimeInterval(1)) // tile 3 變
        let stream = await engine.start(from: FakeProducer(framesToYield: [frame1, frame2]))

        var events: [TileEvent] = []
        for await event in stream { events.append(event) }

        XCTAssertEqual(events.count, 1)                       // 首幀 baseline 不吐；第二幀一個變動
        XCTAssertEqual(events[0].tileX, 1)                    // index 3 → (1,1)
        XCTAssertEqual(events[0].tileY, 1)
        XCTAssertEqual(events[0].dhash, 40 ^ 0xFF)
        XCTAssertEqual(events[0].state, .warm)
    }

    func testFirstFrameUsesDirtyRectsOnly() async {
        let engine = CaptureEngine(grid: grid)
        // 首幀帶 dirtyRect 覆蓋 tile (0,0)，無前一幀可比 → 應吐 (0,0)。
        let frame = TileFrame(dirtyRects: [CGRect(x: 10, y: 10, width: 20, height: 20)],
                              hashes: [1, 2, 3, 4], timestamp: t0)
        let stream = await engine.start(from: FakeProducer(framesToYield: [frame]))

        var events: [TileEvent] = []
        for await event in stream { events.append(event) }

        XCTAssertEqual(events.map { [$0.tileX, $0.tileY] }, [[0, 0]])
    }

    func testNoChangeEmitsNothing() async {
        let engine = CaptureEngine(grid: grid)
        let frame1 = TileFrame(hashes: [10, 20, 30, 40], timestamp: t0)
        let frame2 = TileFrame(hashes: [10, 20, 30, 40], timestamp: t0.addingTimeInterval(1))  // 完全相同
        let stream = await engine.start(from: FakeProducer(framesToYield: [frame1, frame2]))

        var count = 0
        for await _ in stream { count += 1 }
        XCTAssertEqual(count, 0)
    }

    func testStopFinishesStream() async {
        let engine = CaptureEngine(grid: grid)
        let stream = await engine.start(from: NeverEndingProducer())
        await engine.stop()                                  // 停止 → 收掉串流

        var count = 0
        for await _ in stream { count += 1 }                 // 已 finish → 立即結束
        XCTAssertEqual(count, 0)
    }
}
