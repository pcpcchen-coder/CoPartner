import XCTest
import CoPartnerCore
import ScriptNarrator

/// L2 段落摘要（§2 L2）：app 切換 / 時間窗切段，聚合筆數與目標。
final class L2SummarizerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func step(app: String, goal: String, at: Date) -> ActionStep {
        ActionStep(startedAt: at, app: app, category: "c", whatHappened: "w",
                   inferredGoal: goal, confidence: 0.8, artifacts: [], openLoop: false)
    }

    func testAppChangeSplitsSessions() {
        let steps = [
            step(app: "Xcode", goal: "a", at: t0),
            step(app: "Xcode", goal: "b", at: t0.addingTimeInterval(1)),
            step(app: "Safari", goal: "c", at: t0.addingTimeInterval(2)),
        ]
        let out = L2Summarizer.summarize(steps, window: 3600)
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[0].apps, ["Xcode"])
        XCTAssertEqual(out[0].stepCount, 2)
        XCTAssertEqual(out[1].apps, ["Safari"])
    }

    func testTimeWindowSplits() {
        let steps = [
            step(app: "Xcode", goal: "a", at: t0),
            step(app: "Xcode", goal: "b", at: t0.addingTimeInterval(400)),   // 同 app 但 > window
        ]
        XCTAssertEqual(L2Summarizer.summarize(steps, window: 300).count, 2)
    }

    func testSingleAppRunOneSummary() {
        let steps = [
            step(app: "Xcode", goal: "a", at: t0),
            step(app: "Xcode", goal: "b", at: t0.addingTimeInterval(10)),
            step(app: "Xcode", goal: "c", at: t0.addingTimeInterval(20)),
        ]
        let out = L2Summarizer.summarize(steps, window: 300)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].stepCount, 3)
    }

    func testEmptyStepsEmpty() {
        XCTAssertTrue(L2Summarizer.summarize([], window: 300).isEmpty)
    }

    func testSummaryTextMentionsGoals() {
        let out = L2Summarizer.summarize([step(app: "Xcode", goal: "修 build 錯誤", at: t0)], window: 300)
        XCTAssertEqual(out.count, 1)
        XCTAssertTrue(out[0].text.contains("修 build 錯誤"))
    }

    func testStepCountAggregated() {
        let steps = (0..<4).map { step(app: "Xcode", goal: "g\($0)", at: t0.addingTimeInterval(Double($0))) }
        XCTAssertEqual(L2Summarizer.summarize(steps, window: 300).first?.stepCount, 4)
    }
}
