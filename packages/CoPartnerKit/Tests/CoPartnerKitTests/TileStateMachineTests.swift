import XCTest
import CoPartnerCore
import CaptureEngine

/// Tile 冷熱狀態機（§B.6 / §L）。注入 now: 決定性。
final class TileStateMachineTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)
    private func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }

    func testInitialCold() {
        XCTAssertEqual(TileStateMachine().state, .cold)
    }

    func testSingleChangeIsWarm() {
        var m = TileStateMachine()
        XCTAssertEqual(m.update(change: .large, at: t0, periodic: false, hasAXText: false), .warm)
    }

    func testSmallChangeAlsoCountsAsActivity() {
        var m = TileStateMachine()
        XCTAssertEqual(m.update(change: .small, at: t0, periodic: false, hasAXText: false), .warm)
    }

    func testSustainedChangesBecomeHot() {
        var m = TileStateMachine(config: .init(hotThreshold: 4))
        var state = TileEvent.State.cold
        for i in 0..<4 { state = m.update(change: .large, at: at(Double(i) * 0.1), periodic: false, hasAXText: false) }
        XCTAssertEqual(state, .hot)
    }

    func testSustainedPeriodicBecomesDynamic() {
        var m = TileStateMachine(config: .init(hotThreshold: 4))
        var state = TileEvent.State.cold
        for i in 0..<4 { state = m.update(change: .large, at: at(Double(i) * 0.016), periodic: true, hasAXText: false) }
        XCTAssertEqual(state, .dynamic)
    }

    func testAXTextTileNeverDynamic() {
        var m = TileStateMachine(config: .init(hotThreshold: 4))
        var state = TileEvent.State.cold
        for i in 0..<4 { state = m.update(change: .large, at: at(Double(i) * 0.016), periodic: true, hasAXText: true) }
        XCTAssertEqual(state, .hot)   // §L：有 AX 文字 → 封頂 HOT
    }

    func testCoolsToWarmThenCold() {
        var m = TileStateMachine(config: .init(hotThreshold: 2, coldAfter: 2.0))
        _ = m.update(change: .large, at: t0, periodic: false, hasAXText: false)
        _ = m.update(change: .large, at: at(0.1), periodic: false, hasAXText: false)
        XCTAssertEqual(m.state, .hot)
        XCTAssertEqual(m.update(change: .none, at: at(0.5), periodic: false, hasAXText: false), .warm) // 距最後變動 0.4s < 2
        XCTAssertEqual(m.update(change: .none, at: at(5.0), periodic: false, hasAXText: false), .cold) // 距最後變動 4.9s > 2
    }
}
