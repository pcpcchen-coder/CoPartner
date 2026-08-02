import XCTest
import CoPartnerCore
import CloudRouter

/// 出境閘門（威脅 T6 / 不變式 I6）：PIPL 命中整包拒；否則逐欄位遮罩。
final class EgressGateTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    // 假 scrubber：把 "SECRET" 換成 "[遮罩]"。假 PIPL：含 "上海" 即命中。
    private struct FakeScrubber: PIIScrubbing {
        func scrub(_ text: String) -> (clean: String, foundPII: Bool) {
            let cleaned = text.replacingOccurrences(of: "SECRET", with: "[遮罩]")
            return (cleaned, cleaned != text)
        }
    }
    private func gate() -> EgressGate {
        EgressGate(scrubber: FakeScrubber(), piplDetector: { $0.contains("上海") })
    }

    private func step(what: String = "w", goal: String = "g", artifacts: [String] = []) -> ActionStep {
        ActionStep(startedAt: t0, app: "Xcode", category: "editing", whatHappened: what,
                   inferredGoal: goal, confidence: 0.7, artifacts: artifacts, openLoop: false)
    }
    private func envelope(summary: String = "s", openLoop: String = "o", steps: [ActionStep] = [],
                          focusText: String? = nil, clipboard: String? = nil, attention: String? = nil) -> ContextEnvelope {
        EnvelopeBuilder().build(now: t0, steps: steps, sessionSummary: summary, openLoop: openLoop,
                                focusText: focusText, clipboard: clipboard, attentionSummary: attention)
    }

    func testCleanEnvelopePassesUnchanged() {
        guard case .allow(let env) = gate().check(envelope(summary: "普通摘要", clipboard: "沒事")) else {
            return XCTFail("乾淨 envelope 應放行")
        }
        XCTAssertEqual(env.clipboardRecent, "沒事")
        XCTAssertEqual(env.actionScript.sessionSummary, "普通摘要")
    }

    func testPIIFieldsScrubbedBeforeAllow() {
        guard case .allow(let env) = gate().check(envelope(clipboard: "my SECRET token")) else {
            return XCTFail()
        }
        XCTAssertEqual(env.clipboardRecent, "my [遮罩] token")
    }

    func testPIPLHitBlocksWholeEnvelope() {
        guard case .blocked(let reason) = gate().check(envelope(attention: "注視上海團隊名冊")) else {
            return XCTFail("PIPL 命中應整包拒")
        }
        XCTAssertEqual(reason, "attention_summary")
    }

    func testScrubberAppliedToAllTextFields() {
        let env = envelope(summary: "SECRET 摘要",
                           steps: [step(what: "貼上 SECRET", artifacts: ["SECRET.txt"])],
                           clipboard: "SECRET")
        guard case .allow(let out) = gate().check(env) else { return XCTFail() }
        XCTAssertEqual(out.actionScript.sessionSummary, "[遮罩] 摘要")
        XCTAssertEqual(out.actionScript.recentSteps.first?.whatHappened, "貼上 [遮罩]")
        XCTAssertEqual(out.actionScript.recentSteps.first?.artifacts.first, "[遮罩].txt")
        XCTAssertEqual(out.clipboardRecent, "[遮罩]")
    }

    func testBlockedReasonNamesField() {
        let env = envelope(steps: [step(what: "在上海辦公室登入")])
        guard case .blocked(let reason) = gate().check(env) else { return XCTFail() }
        XCTAssertEqual(reason, "step0.whatHappened")
    }
}
