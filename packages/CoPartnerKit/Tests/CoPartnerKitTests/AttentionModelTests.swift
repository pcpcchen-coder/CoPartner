import XCTest
import Foundation
import CoreGraphics
import CaptureEngine

/// 事件加權注意力能量模型（ADR-0006 / §B.3.1）的回歸測試。
/// 透過注入 `now:` 讓時間相關的衰減邏輯可決定性驗證（對齊 EscalationPolicy.decide(_:now:)）。
final class AttentionModelTests: XCTestCase {
    /// 固定參考時間，讓所有衰減計算可預測。
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)

    func testClickSetsEnergyToPeakAndReturnsTrue() async {
        let model = AttentionModel(now: t0)
        let forced = await model.update(.click, now: t0)
        XCTAssertTrue(forced, "點擊是動作起點，應要求呼叫端立即強制高解析擷取")
        let energy = await model.currentEnergy
        XCTAssertEqual(energy, 1.0, accuracy: 1e-9, "點擊應把能量拉到峰值 1.0")
    }

    func testIdleReturnsFalseAndDoesNotForceCapture() async {
        let model = AttentionModel(now: t0)
        let forced = await model.update(.idle, now: t0)
        XCTAssertFalse(forced, "靜置不應強制擷取")
        let energy = await model.currentEnergy
        XCTAssertEqual(energy, 0.0, accuracy: 1e-9, "初始靜置能量應為 0")
    }

    func testHighSpeedMoveStaysBelowHotBand() async {
        let model = AttentionModel(now: t0)
        _ = await model.update(.move(speed: 1.0), now: t0)   // 最快速度：純過渡，不升級
        let energy = await model.currentEnergy
        XCTAssertLessThan(energy, 0.7, "快速滑動只是過渡，能量不應進入 HOT 帶")
        XCTAssertEqual(energy, 0.0, accuracy: 1e-9, "speed=1 → 0.3·(1−1)=0")
    }

    func testDragMaintainsAtLeast085Energy() async {
        let model = AttentionModel(now: t0)
        _ = await model.update(.drag, now: t0)
        let energy = await model.currentEnergy
        XCTAssertGreaterThanOrEqual(energy, 0.85, "拖曳進行中應維持高注意力")
    }

    func testScrollMaintainsAtLeast06Energy() async {
        let model = AttentionModel(now: t0)
        _ = await model.update(.scroll, now: t0)
        let energy = await model.currentEnergy
        XCTAssertGreaterThanOrEqual(energy, 0.6, "捲動屬閱讀，注意力中高")
    }

    func testEnergyDecaysAcrossHalfLife() async {
        let model = AttentionModel(now: t0)
        _ = await model.update(.click, now: t0)                        // 能量 → 1.0
        _ = await model.update(.idle, now: t0.addingTimeInterval(2))   // 經過一個 half-life(2s)
        let energy = await model.currentEnergy
        XCTAssertEqual(energy, 0.5, accuracy: 0.01, "一個 half-life 後能量應約減半")
    }

    func testEnergyBandThresholds() async {
        let model = AttentionModel(now: t0)
        _ = await model.update(.click, now: t0)                              // 1.0
        // 隨時間衰減，逐帶檢查 fps 落點（HOT → 升高 → WARM → COLD）；
        // 每次 captureParams 都會推進內部時鐘，故為累積衰減序列。
        let hot = await model.captureParams(now: t0)                         // 1.0 → HOT
        XCTAssertEqual(hot.fps, 8); XCTAssertEqual(hot.radiusPt, 400); XCTAssertEqual(hot.scale, 2.0)
        let high = await model.captureParams(now: t0.addingTimeInterval(2))  // ~0.5 → 升高
        XCTAssertEqual(high.fps, 4)
        let warm = await model.captureParams(now: t0.addingTimeInterval(4))  // ~0.25 → WARM
        XCTAssertEqual(warm.fps, 2)
        let cold = await model.captureParams(now: t0.addingTimeInterval(7))  // ~0.09 → COLD
        XCTAssertEqual(cold.fps, 0.2); XCTAssertEqual(cold.scale, 0.5)
    }

    func testPointUpdatesCenter() async {
        let model = AttentionModel(now: t0)
        let p = CGPoint(x: 42, y: 99)
        _ = await model.update(.idle, at: p, now: t0)   // 即使 idle，只要帶座標就更新 center
        let center = await model.center
        XCTAssertEqual(center, p, "帶座標的事件應更新 attention region 中心，與 signal 種類無關")
    }
}
