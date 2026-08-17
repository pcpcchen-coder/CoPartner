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
    /// 這是除錯預覽，不是真提議。
    ///
    /// 存在的理由是安全而不是方便：預覽浮層和真浮層長得一模一樣。
    /// 使用者若把預覽當成真的（或反過來把真的當成預覽），確認閘門的意義就沒了——
    /// 所以 UI **必須**依這個旗標畫出無法忽略的標示，而且預覽的主要按鈕不可寫「執行」。
    public let isPreview: Bool

    public init(actionSummary: String, modelRationale: String, risk: ActionRisk,
                riskLabel: String, localRiskReason: String?,
                approveTitle: String, approveWillExecute: Bool,
                isPreview: Bool = false) {
        self.actionSummary = actionSummary
        self.modelRationale = modelRationale
        self.risk = risk
        self.riskLabel = riskLabel
        self.localRiskReason = localRiskReason
        self.approveWillExecute = approveWillExecute
        self.approveTitle = approveTitle
        self.isPreview = isPreview
    }

    /// 由待確認的提議組出顯示內容。
    public static func make(action: ProposedAction,
                            risk: ActionRisk,
                            policy: TakeoverContract.Policy,
                            classifier: RiskClassifier = RiskClassifier(),
                            isPreview: Bool = false) -> TakeoverHUDPresentation {
        // 預覽一律不執行——不管 policy 是什麼。這條 && 是預覽不會變成真動作的第一道保險
        // （第二道在 AppCoordinator：預覽的決定回呼根本碰不到 executor）。
        let willExecute = (policy != .suggestOnly) && !isPreview
        return TakeoverHUDPresentation(
            actionSummary: action.kind.summary,          // 本地產生，非雲端描述
            modelRationale: action.rationale,
            risk: risk,
            riskLabel: Self.label(for: risk),
            // high 一律附本地原因；medium/low 沒有也正常。
            localRiskReason: classifier.reasonForHigh(action),
            approveTitle: Self.approveTitle(willExecute: willExecute, isPreview: isPreview),
            approveWillExecute: willExecute,
            isPreview: isPreview)
    }

    private static func approveTitle(willExecute: Bool, isPreview: Bool) -> String {
        if isPreview { return "關閉預覽（不會執行）" }
        return willExecute ? "執行" : "僅建議（不會執行）"
    }

    /// 除錯預覽用的假提議（step 54）。
    ///
    /// 真執行端（XPC + sandbox-exec）接上之前，這是唯一能目視驗證浮層的方式：
    /// 版面、位置、按鈕、跨 app 浮動與跨 Space 行為都得在真機上看過才算數。
    ///
    /// 刻意**走完整條真的產生路徑**——同一個 `RiskClassifier`、同一個 `make`——
    /// 而不是手寫一組漂亮的欄位。手寫的預覽只證明「假資料畫得出來」，
    /// 證明不了真提議會長成什麼樣；那種預覽通過了也不代表什麼。
    ///
    /// 選 `rm -rf` 當樣本是因為它會踩到 high 分級**並帶出本地原因**，
    /// 一次驗到最需要目視確認的那條路徑（紅色標頭與原因文字都得出現）。
    public static func previewFixture(classifier: RiskClassifier = RiskClassifier())
        -> TakeoverHUDPresentation {
        let action = ProposedAction(
            kind: .shell(argv: ["rm", "-rf", "~/Documents/專案備份"]),
            rationale: "（預覽假資料）看你剛在整理專案，先把舊備份資料夾清掉可以釋出空間。")
        return make(action: action,
                    risk: classifier.classify(action),
                    policy: .confirmEach,
                    classifier: classifier,
                    isPreview: true)
    }

    /// public 而非 internal：測試在別的 module，看不到 internal 成員。
    /// （同 `SSEFrameParser.splitField`——這個坑踩過兩次了，新增給測試用的
    /// helper 時記得檢查可見性。）
    public static func label(for risk: ActionRisk) -> String {
        switch risk {
        case .low: return "低風險"
        case .medium: return "中風險"
        case .high: return "高風險"
        }
    }
}
