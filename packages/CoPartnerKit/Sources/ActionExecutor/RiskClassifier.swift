import Foundation
import CoPartnerCore
// 設計：sandbox-threat-model.md T1/T2/T5/T9、I2/I3。
// **與模型推理無關的本地規則**：無論雲端說什麼理由，分級只看動作本身（T1 注入的最後防線）。
// 對外通訊無條件 high；shell 危險 pattern → high、否則 medium（shell 永不 low）；
// 秘密路徑讀寫 high；UI 點按/截圖 low；鍵盤 chord medium（⌘Q/⌘⌫ 類可觸發破壞）。

public struct RiskClassifier: Sendable {
    private let detector = DangerousCommandDetector()
    public init() {}

    public func classify(_ action: ProposedAction) -> ActionRisk {
        switch action.kind {
        case .outboundComms:
            return .high                                              // 外顯難撤回（T5/T9）
        case .shell(let argv):
            return detector.reason(argv: argv) != nil ? .high : .medium
        case .writeFile(let path, _):
            return DangerousCommandDetector.touchesSecretPath(path) ? .high : .medium
        case .readFile(let path):
            return DangerousCommandDetector.touchesSecretPath(path) ? .high : .low
        case .keypress:
            return .medium
        case .screenshot, .click, .typeText, .scroll:
            return .low
        }
    }

    /// HUD 顯示用：high 的白話原因（不信任雲端的自述，本地產生）。
    public func reasonForHigh(_ action: ProposedAction) -> String? {
        switch action.kind {
        case .outboundComms(let kind, let target): return "將以你的身分對外送出（\(kind) → \(target)）"
        case .shell(let argv): return detector.reason(argv: argv)
        case .writeFile(let path, _) where DangerousCommandDetector.touchesSecretPath(path): return "寫入秘密路徑 \(path)"
        case .readFile(let path) where DangerousCommandDetector.touchesSecretPath(path): return "讀取秘密路徑 \(path)"
        default: return nil
        }
    }
}
