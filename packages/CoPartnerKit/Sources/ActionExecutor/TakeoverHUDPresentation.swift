import Foundation
import CoPartnerCore
// 設計：v1 §F（介入 HUD）+ sandbox-threat-model.md T1/T2/I2。
// 把「一個待確認的提議該怎麼顯示」抽成純值——SwiftUI 只負責畫，判斷全在這裡、CI 可測。
//
// 為什麼顯示邏輯值得單獨測：確認閘門的安全性**取決於使用者看到的東西是否正確**。
// 顯示錯了（把不執行的說成會執行、high 風險不顯示原因、動作原文被摘要掉），
// 閘門就形同虛設——而這種錯誤在 UI 裡看起來一切正常。

public struct TakeoverHUDPresentation: Sendable, Equatable {
    /// 使用者能做的三個決定。
    public enum Decision: Sendable, Equatable { case approve, skip, stop }

    /// 動作原文——**本地從結構化欄位產生**，不是雲端給的描述。
    /// 使用者確認的必須是「實際會執行什麼」，不是模型「說」它要做什麼。
    public let actionSummary: String
    /// Claude 附的理由。**標示為不可信來源**：T1 提示注入可以讓模型寫出很安撫人的理由。
    public let modelRationale: String
    public let risk: ActionRisk
    public let riskLabel: String
    /// high 風險的原因，**由本地 RiskClassifier 產生**，與模型推理無關（T1 的最後防線）。
    public let localRiskReason: String?
    /// 主要按鈕的標題——依 policy 變化。
    public let approveTitle: String
    /// 按下主要按鈕**會不會真的執行**。suggestOnly 為 false。
    ///
    /// 這個欄位存在的理由：`suggestOnly` 下狀態機的 `approve()` 回 nil、不鑄造 token、
    /// 什麼都不會執行。若 HUD 仍畫成「執行」，使用者會以為自己核准了某件事而它沒發生——
    /// 反過來也一樣危險：以為沒事發生但其實執行了。按鈕文字必須誠實反映後果。
    public let approveWillExecute: Bool

    public init(actionSummary: String, modelRationale: String, risk: ActionRisk,
                riskLabel: String, localRiskReason: String?,
                approveTitle: String, approveWillExecute: Bool) {
        self.actionSummary = actionSummary
        self.modelRationale = modelRationale
        self.risk = risk
        self.riskLabel = riskLabel
        self.localRiskReason = localRiskReason
        self.approveWillExecute = approveWillExecute
        self.approveTitle = approveTitle
    }

    /// 由待確認的提議組出顯示內容。
    public static func make(action: ProposedAction,
                            risk: ActionRisk,
                            policy: TakeoverContract.Policy,
                            classifier: RiskClassifier = RiskClassifier()) -> TakeoverHUDPresentation {
        let willExecute = (policy != .suggestOnly)
        return TakeoverHUDPresentation(
            actionSummary: action.kind.summary,          // 本地產生，非雲端描述
            modelRationale: action.rationale,
            risk: risk,
            riskLabel: Self.label(for: risk),
            // high 一律附本地原因；medium/low 沒有也正常。
            localRiskReason: classifier.reasonForHigh(action),
            approveTitle: willExecute ? "執行" : "僅建議（不會執行）",
            approveWillExecute: willExecute)
    }

    static func label(for risk: ActionRisk) -> String {
        switch risk {
        case .low: return "低風險"
        case .medium: return "中風險"
        case .high: return "高風險"
        }
    }
}
