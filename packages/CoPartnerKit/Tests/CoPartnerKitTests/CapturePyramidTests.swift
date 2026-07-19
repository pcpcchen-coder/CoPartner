import XCTest
import Foundation
import CaptureEngine

/// 多解析度金字塔能量→三層參數映射（§B.5 / §B.6）。
final class CapturePyramidTests: XCTestCase {
    func testHotBand() {
        let p = CapturePyramid.forEnergy(0.9)
        XCTAssertEqual(p.focus, CaptureLayer(region: .focus(radiusPt: 400), scale: 2.0, fps: 8))
        XCTAssertEqual(p.periphery, CaptureLayer(region: .focus(radiusPt: 800), scale: 1.0, fps: 4))
        XCTAssertEqual(p.overview, CaptureLayer(region: .fullScreen, scale: 0.5, fps: 1, maxDimensionPt: 1024))
    }

    func testElevatedBand() {
        let p = CapturePyramid.forEnergy(0.5)
        XCTAssertEqual(p.focus.region, .focus(radiusPt: 300))
        XCTAssertEqual(p.focus.fps, 4)
    }

    func testWarmBand() {
        let p = CapturePyramid.forEnergy(0.2)
        XCTAssertEqual(p.focus.region, .focus(radiusPt: 250))
        XCTAssertEqual(p.focus.fps, 2)
    }

    func testColdBandOnlyOverviewActive() {
        let p = CapturePyramid.forEnergy(0.05)
        XCTAssertFalse(p.focus.isActive)       // fps 0
        XCTAssertFalse(p.periphery.isActive)
        XCTAssertTrue(p.overview.isActive)     // 心跳
        XCTAssertEqual(p.overview.fps, 0.2)
        XCTAssertEqual(p.overview.region, .fullScreen)
    }

    func testBandBoundaries() {
        XCTAssertEqual(CapturePyramid.forEnergy(0.7).focus.fps, 8)      // 0.7 → HOT
        XCTAssertEqual(CapturePyramid.forEnergy(0.699).focus.fps, 4)    // → 升高
        XCTAssertEqual(CapturePyramid.forEnergy(0.4).focus.fps, 4)      // 0.4 → 升高
        XCTAssertEqual(CapturePyramid.forEnergy(0.399).focus.fps, 2)    // → WARM
        XCTAssertEqual(CapturePyramid.forEnergy(0.15).focus.fps, 2)     // 0.15 → WARM
        XCTAssertFalse(CapturePyramid.forEnergy(0.149).focus.isActive)  // → COLD
    }

    func testOverviewAlwaysFullScreenAndCappedTo1024() {
        for energy in [0.9, 0.5, 0.2, 0.05] {
            let p = CapturePyramid.forEnergy(energy)
            XCTAssertEqual(p.overview.region, .fullScreen, "energy \(energy)")
            XCTAssertEqual(p.overview.maxDimensionPt, 1024, "energy \(energy)")
        }
    }

    func testFocusRegionLargerWhenHotterAndPeripheryBiggerThanFocus() {
        XCTAssertGreaterThan(radius(CapturePyramid.forEnergy(0.9).focus.region),
                             radius(CapturePyramid.forEnergy(0.2).focus.region))   // HOT 焦點 > WARM
        let hot = CapturePyramid.forEnergy(0.9)
        XCTAssertGreaterThan(radius(hot.periphery.region), radius(hot.focus.region)) // 周邊 > 焦點
    }

    func testAttentionModelPyramidHotAfterClick() async {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        let model = AttentionModel(now: t0)
        _ = await model.update(.click, now: t0)               // energy → 1.0
        let p = await model.capturePyramid(now: t0)
        XCTAssertEqual(p.focus.fps, 8)                         // HOT
        XCTAssertEqual(p.focus.scale, 2.0)
    }

    func testAttentionModelPyramidColdAfterDecay() async {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        let model = AttentionModel(now: t0)
        _ = await model.update(.click, now: t0)               // 1.0
        // 經過多個 half-life 後衰減到 COLD
        let p = await model.capturePyramid(now: t0.addingTimeInterval(20))
        XCTAssertFalse(p.focus.isActive)                      // 只剩概覽心跳
        XCTAssertTrue(p.overview.isActive)
    }

    private func radius(_ region: CaptureLayer.Region) -> Double {
        if case .focus(let r) = region { return r }
        return -1
    }
}
