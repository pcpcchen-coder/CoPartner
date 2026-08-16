import Foundation
import CoPartnerCore
// 設計：§5 fallback 階梯。依 availability 選 tier；模型回 nil 時級聯下降；
// 規則式在底、保證有輸出，故 narrate 回**非 optional**（降級但不中斷）。

public struct NarrationLadder: Sendable {
    private let fm: (any NarrationBackend)?
    private let qwen: (any NarrationBackend)?
    private let rule: any NarrationBackend

    public init(fm: (any NarrationBackend)? = nil,
                qwen: (any NarrationBackend)? = nil,
                rule: any NarrationBackend = RuleBasedNarrator()) {
        self.fm = fm
        self.qwen = qwen
        self.rule = rule
    }

    /// 依 availability 由上而下嘗試；每層回 nil 就下降。rule 保底 → 回非 optional。
    public func narrate(_ lines: [String], fmAvailable: Bool, qwenReachable: Bool) async -> ActionStep {
        await narrateReportingTier(lines, fmAvailable: fmAvailable, qwenReachable: qwenReachable).step
    }

    /// 同 `narrate`，但**一併回報實際命中的那層**。
    ///
    /// 為什麼需要：M4 驗收要驗「關掉 Apple Intelligence 會 fallback 到規則式且不中斷」，
    /// 而光看回傳的 `ActionStep` 分不出它是 3B 產的還是模板湊的——除非去比對
    /// `inferredGoal == "（規則式推測，未使用模型）"` 這種字串特徵，那既脆弱、又會在
    /// 文案一改就默默失效。讓階梯直說自己走了哪層，是唯一可靠的訊號。
    public func narrateReportingTier(_ lines: [String],
                                     fmAvailable: Bool,
                                     qwenReachable: Bool) async -> NarrationResult {
        if fmAvailable, let fm, let step = await fm.narrate(lines) {
            return NarrationResult(step: step, tier: .foundationModels)
        }
        if qwenReachable, let qwen, let step = await qwen.narrate(lines) {
            return NarrationResult(step: step, tier: .qwenMLX)
        }
        if let step = await rule.narrate(lines) {
            return NarrationResult(step: step, tier: .ruleBased)
        }
        // rule 對非空輸入永不回 nil；只有空輸入會到這，給一個最小 placeholder。
        let placeholder = ActionStep(startedAt: Date(), app: "未知", category: "operating",
                                     whatHappened: "（無事件）", inferredGoal: "（規則式推測，未使用模型）",
                                     confidence: 0, artifacts: [], openLoop: false)
        return NarrationResult(step: placeholder, tier: .ruleBased)
    }
}

/// 一次敘事的結果：step 本身 + 它出自階梯哪一層。
public struct NarrationResult: Sendable {
    public let step: ActionStep
    public let tier: NarrationTier
    public init(step: ActionStep, tier: NarrationTier) {
        self.step = step
        self.tier = tier
    }
}
