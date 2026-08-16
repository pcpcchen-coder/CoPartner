import Foundation
import CoPartnerCore
// 設計：docs/design/v2.1_action-script-narrator.md §2（L1 敘事）+ §5（fallback 階梯）。
// 把「產 ActionStep 的模型」抽成可注入 protocol：真 FoundationModels / Qwen MLX 藏在後端，
// CI 用規則式 / 假 backend 驗編排。階梯選擇見 NarrationLadder（step 39）。

/// L1 敘事後端：吃 L0 事件日誌行，產一個 `ActionStep`（不可得則回 nil，交由階梯下降）。
public protocol NarrationBackend: Sendable {
    func narrate(_ lines: [String]) async -> ActionStep?
}

/// 敘事階梯的三層（§5：FoundationModels → Qwen MLX → 純規則模板）。
public enum NarrationTier: Sendable, Equatable {
    case foundationModels
    case qwenMLX
    case ruleBased

    /// 選單顯示用的短標籤——讓使用者一眼看出這句敘事是誰產的（M4 fallback 驗收要看）。
    public var displayLabel: String {
        switch self {
        case .foundationModels: return "本地 3B"
        case .qwenMLX: return "Qwen MLX"
        case .ruleBased: return "規則式"
        }
    }
}
