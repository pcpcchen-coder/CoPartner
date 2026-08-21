import Foundation
import CoPartnerCore
// 設計：sandbox-threat-model.md T1/T2/T5/T9、I2/I3。
// **與模型推理無關的本地規則**：無論雲端說什麼理由，分級只看動作本身（T1 注入的最後防線）。
// 對外通訊無條件 high；shell 危險 pattern → high、否則 medium（shell 永不 low）；
// 秘密路徑讀寫 high；UI 點按/截圖 low；鍵盤 chord medium，但**難以復原的組合鍵 high**
// （⌘Q／⌘⌫／⌘⇧⌫／⌥⌘⎋ 這類，見 `DestructiveKeyChords`）。
//
// step 53.6：`.keypress` 原本一律 medium。那等於把「⌘C」和「清空垃圾桶」放在同一格——
// 在 autoBounded 政策下兩者都要問人所以看不出差別，但分級的意義本來就不只是「要不要問」，
// 而是 HUD 上要不要把後果講出來。解析不了的組合鍵也算 high：不知道它會做什麼
// 不代表它無害，那更該問人。

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
        case .keypress(let chord):
            return DestructiveKeyChords.consequence(ofRaw: chord) != nil ? .high : .medium
        case .typeText(let text):
            // 帶換行的輸入 ≠ 單純打字：它等同「打完再按 Enter」，而 Enter 是
            // 送出表單／寄信／執行命令的那一下。文字本身無害，那一下不一定。
            return text.contains(where: \.isNewline) ? .medium : .low
        case .screenshot, .click, .scroll:
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
        case .keypress(let chord): return DestructiveKeyChords.consequence(ofRaw: chord)
        default: return nil
        }
    }
}
