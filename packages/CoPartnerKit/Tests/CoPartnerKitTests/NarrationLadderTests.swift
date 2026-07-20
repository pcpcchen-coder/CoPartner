import XCTest
import CoPartnerCore
import ScriptNarrator

/// 敘事階梯（§5）：availability 選層 + nil 級聯 + 規則式保底（回非 optional）。
final class NarrationLadderTests: XCTestCase {
    private struct FixedBackend: NarrationBackend {
        let step: ActionStep?
        func narrate(_ lines: [String]) async -> ActionStep? { step }
    }
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let lines = ["[00:00:01.000] TYPE field=e text=\"hi\""]

    private func mkStep(_ goal: String) -> ActionStep {
        ActionStep(startedAt: t0, app: "X", category: "c", whatHappened: "w",
                   inferredGoal: goal, confidence: 1, artifacts: [], openLoop: false)
    }

    func testFMAvailableUsesFM() async {
        let a = mkStep("fm"), b = mkStep("qwen")
        let ladder = NarrationLadder(fm: FixedBackend(step: a), qwen: FixedBackend(step: b), rule: RuleBasedNarrator())
        let r = await ladder.narrate(lines, fmAvailable: true, qwenReachable: true)
        XCTAssertEqual(r.id, a.id)
    }

    func testFMUnavailableSkipsFM() async {
        let a = mkStep("fm"), b = mkStep("qwen")
        let ladder = NarrationLadder(fm: FixedBackend(step: a), qwen: FixedBackend(step: b), rule: RuleBasedNarrator())
        let r = await ladder.narrate(lines, fmAvailable: false, qwenReachable: true)
        XCTAssertEqual(r.id, b.id)
    }

    func testFMNilCascadesToQwen() async {
        let b = mkStep("qwen")
        let ladder = NarrationLadder(fm: FixedBackend(step: nil), qwen: FixedBackend(step: b), rule: RuleBasedNarrator())
        let r = await ladder.narrate(lines, fmAvailable: true, qwenReachable: true)
        XCTAssertEqual(r.id, b.id)
    }

    func testBothModelsSkippedUsesRule() async {
        let ladder = NarrationLadder(fm: FixedBackend(step: mkStep("fm")),
                                     qwen: FixedBackend(step: mkStep("qwen")),
                                     rule: RuleBasedNarrator(now: t0))
        let r = await ladder.narrate(lines, fmAvailable: false, qwenReachable: false)
        XCTAssertEqual(r.confidence, 0.3, accuracy: 1e-9)   // rule-based 特徵信心度
    }

    func testAllModelsNilUsesRule() async {
        let ladder = NarrationLadder(fm: FixedBackend(step: nil), qwen: FixedBackend(step: nil), rule: RuleBasedNarrator(now: t0))
        let r = await ladder.narrate(lines, fmAvailable: true, qwenReachable: true)
        XCTAssertEqual(r.confidence, 0.3, accuracy: 1e-9)
    }

    func testEmptyLinesStillReturnsStep() async {
        let ladder = NarrationLadder(fm: FixedBackend(step: nil), qwen: FixedBackend(step: nil), rule: RuleBasedNarrator())
        let r = await ladder.narrate([], fmAvailable: true, qwenReachable: true)
        XCTAssertEqual(r.confidence, 0, accuracy: 1e-9)     // 空輸入 → placeholder（仍非 nil）
    }
}
