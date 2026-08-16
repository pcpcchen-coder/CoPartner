import XCTest
import CoPartnerCore
import ScriptNarrator

/// 階梯回報實際命中的層（step 42）。
///
/// 為什麼值得單獨測：M4 驗收要驗「關掉 Apple Intelligence 會 fallback 到規則式且不中斷」。
/// 沒有 tier 回報，唯一的判別方式是比對 `inferredGoal` 的固定字串——文案一改就默默失效，
/// 而且失效方式是「看起來還是綠的」。這組測試把 tier 與各層的對應釘死。
final class NarrationTierReportingTests: XCTestCase {
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

    func testReportsFoundationModelsWhenFMAnswers() async {
        let ladder = NarrationLadder(fm: FixedBackend(step: mkStep("fm")),
                                     qwen: FixedBackend(step: mkStep("qwen")),
                                     rule: RuleBasedNarrator())
        let r = await ladder.narrateReportingTier(lines, fmAvailable: true, qwenReachable: true)
        XCTAssertEqual(r.tier, .foundationModels)
    }

    /// 這是 M4 驗收的核心情境：Apple Intelligence 關掉 → fmAvailable false → 應落到規則式。
    func testReportsRuleBasedWhenModelUnavailable() async {
        let ladder = NarrationLadder(fm: FixedBackend(step: mkStep("fm")),
                                     qwen: nil,
                                     rule: RuleBasedNarrator(now: t0))
        let r = await ladder.narrateReportingTier(lines, fmAvailable: false, qwenReachable: false)
        XCTAssertEqual(r.tier, .ruleBased)
        XCTAssertFalse(r.step.whatHappened.isEmpty, "降級但不中斷：仍要有可讀輸出")
    }

    func testReportsQwenWhenFMCascades() async {
        let ladder = NarrationLadder(fm: FixedBackend(step: nil),
                                     qwen: FixedBackend(step: mkStep("qwen")),
                                     rule: RuleBasedNarrator())
        let r = await ladder.narrateReportingTier(lines, fmAvailable: true, qwenReachable: true)
        XCTAssertEqual(r.tier, .qwenMLX)
    }

    func testEmptyInputPlaceholderIsReportedAsRuleBased() async {
        let ladder = NarrationLadder(fm: FixedBackend(step: nil), qwen: nil, rule: RuleBasedNarrator())
        let r = await ladder.narrateReportingTier([], fmAvailable: true, qwenReachable: true)
        XCTAssertEqual(r.tier, .ruleBased)
    }

    /// `narrate` 是 `narrateReportingTier` 的薄包裝——兩者不可分歧。
    func testNarrateAgreesWithTierReportingVariant() async {
        let step = mkStep("fm")
        let ladder = NarrationLadder(fm: FixedBackend(step: step), qwen: nil, rule: RuleBasedNarrator())
        let plain = await ladder.narrate(lines, fmAvailable: true, qwenReachable: true)
        let reported = await ladder.narrateReportingTier(lines, fmAvailable: true, qwenReachable: true)
        XCTAssertEqual(plain.id, reported.step.id)
    }

    func testTierLabelsAreDistinct() {
        let labels = Set([NarrationTier.foundationModels.displayLabel,
                          NarrationTier.qwenMLX.displayLabel,
                          NarrationTier.ruleBased.displayLabel])
        XCTAssertEqual(labels.count, 3, "選單要靠標籤分辨層級，不可重複")
    }
}
