import XCTest
import CoreGraphics
import CoPartnerCore
import CaptureEngine

/// CaptureEngine 整合冷熱狀態機（step 23）：TileEvent 帶真狀態，非 .warm 佔位。
final class CaptureEngineStateTests: XCTestCase {
    private let grid = TileGrid(width: 256, height: 256, tileSize: 128)   // 4 tiles
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)

    private struct FakeProducer: FrameProducer {
        let framesToYield: [TileFrame]
        func frames() -> AsyncStream<TileFrame> {
            AsyncStream { c in
                for f in framesToYield { c.yield(f) }
                c.finish()
            }
        }
        func stop() {}
    }

    /// 基準幀 + tile(1,1) 每幀變動的 N 幀（index 3 每次不同 hash）。
    private func changingFrames(count: Int, interval: Double, app: String? = nil) -> [TileFrame] {
        var frames: [TileFrame] = []
        var hashes: [UInt64] = [10, 20, 30, 40]
        frames.append(TileFrame(app: app, hashes: hashes, timestamp: t0))
        for i in 1...count {
            hashes[3] = UInt64(1000 + i)
            frames.append(TileFrame(app: app, hashes: hashes, timestamp: t0.addingTimeInterval(Double(i) * interval)))
        }
        return frames
    }

    private func states(from engine: CaptureEngine, frames: [TileFrame]) async -> [TileEvent.State] {
        let stream = await engine.start(from: FakeProducer(framesToYield: frames))
        var result: [TileEvent.State] = []
        for await event in stream where event.tileX == 1 && event.tileY == 1 {
            result.append(event.state)
        }
        return result
    }

    func testStatesEscalateWarmToHot() async {
        let engine = CaptureEngine(grid: grid, stateConfig: .init(hotThreshold: 3, coldAfter: 2))
        let s = await states(from: engine, frames: changingFrames(count: 5, interval: 0.1))
        XCTAssertEqual(s, [.warm, .warm, .hot, .hot, .hot])   // 基準幀不吐；連續達 3 → HOT
    }

    func testPeriodicChangesBecomeDynamic() async {
        let engine = CaptureEngine(grid: grid, stateConfig: .init(hotThreshold: 3))
        let s = await states(from: engine, frames: changingFrames(count: 10, interval: 1.0 / 60.0))
        XCTAssertEqual(s.last, .dynamic)   // 60fps 規律 → 影片
    }

    func testOverrideKeepsExcludedAppAtHot() async {
        var overrides = CaptureOverrides()
        overrides.setNeverDynamic("VideoApp")
        let engine = CaptureEngine(grid: grid, overrides: overrides, stateConfig: .init(hotThreshold: 3))
        let s = await states(from: engine, frames: changingFrames(count: 10, interval: 1.0 / 60.0, app: "VideoApp"))
        XCTAssertEqual(s.last, .hot)       // app 被排除 DYNAMIC → 封頂 HOT
    }
}
