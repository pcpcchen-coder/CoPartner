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
        if fmAvailable, let fm, let step = await fm.narrate(lines) { return step }
        if qwenReachable, let qwen, let step = await qwen.narrate(lines) { return step }
        if let step = await rule.narrate(lines) { return step }
        // rule 對非空輸入永不回 nil；只有空輸入會到這，給一個最小 placeholder。
        return ActionStep(startedAt: Date(), app: "未知", category: "operating",
                          whatHappened: "（無事件）", inferredGoal: "（規則式推測，未使用模型）",
                          confidence: 0, artifacts: [], openLoop: false)
    }
}
