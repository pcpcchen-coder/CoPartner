import XCTest
import CoPartnerCore
import MemoryStore

/// L1 熱環（§3）：容量 + 時間窗雙淘汰。
final class L1HotBufferTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func step(_ goal: String, at: Date) -> ActionStep {
        ActionStep(startedAt: at, app: "Xcode", category: "editing",
                   whatHappened: "x", inferredGoal: goal, confidence: 0.5,
                   artifacts: [], openLoop: false)
    }

    func testWithinCapacityKeepsAll() {
        var buf = L1HotBuffer(capacity: 10, window: 900)
        for i in 0..<5 { buf.append(step("g\(i)", at: t0), at: t0) }
        XCTAssertEqual(buf.count, 5)
        XCTAssertEqual(buf.recentSteps(now: t0).count, 5)
    }

    func testOverCapacityEvictsOldest() {
        var buf = L1HotBuffer(capacity: 3, window: 9999)
        for i in 0..<5 { buf.append(step("g\(i)", at: t0), at: t0) }
        XCTAssertEqual(buf.recentSteps(now: t0).map { $0.inferredGoal }, ["g2", "g3", "g4"])
    }

    func testEntriesOlderThanWindowDropped() {
        var buf = L1HotBuffer(capacity: 100, window: 300)   // 5 min 窗
        buf.append(step("old", at: t0), at: t0)
        buf.append(step("new", at: t0.addingTimeInterval(290)), at: t0.addingTimeInterval(290))
        let now = t0.addingTimeInterval(400)                // old 已超窗、new 仍在
        XCTAssertEqual(buf.recentSteps(now: now).map { $0.inferredGoal }, ["new"])
    }

    func testRecentStepsNewestLast() {
        var buf = L1HotBuffer(capacity: 10, window: 9999)
        buf.append(step("a", at: t0), at: t0)
        buf.append(step("b", at: t0.addingTimeInterval(1)), at: t0.addingTimeInterval(1))
        XCTAssertEqual(buf.recentSteps(now: t0.addingTimeInterval(2)).map { $0.inferredGoal }, ["a", "b"])
    }

    func testL0AndStepsIndependentCaps() {
        var buf = L1HotBuffer(capacity: 2, window: 9999)
        buf.appendL0("l0-a", at: t0)
        buf.appendL0("l0-b", at: t0)
        buf.appendL0("l0-c", at: t0)
        buf.append(step("s", at: t0), at: t0)
        XCTAssertEqual(buf.recentL0(now: t0), ["l0-b", "l0-c"])   // l0 環淘汰不影響 steps
        XCTAssertEqual(buf.count, 1)
    }

    func testEmptyReturnsEmpty() {
        let buf = L1HotBuffer(capacity: 5, window: 900)
        XCTAssertTrue(buf.recentSteps(now: t0).isEmpty)
        XCTAssertTrue(buf.recentL0(now: t0).isEmpty)
    }
}
