import Foundation
import CoPartnerCore
// 設計：sandbox-threat-model.md R2 ＋ backlog step 53.6-B。
//
// UI 動作（點按 / 輸入 / 捲動）**不經 shell 沙箱**——它們天生就在使用者的 session 權限內，
// 沒有 sbpl 可以兜底。所以這一層要守的東西跟 `CallerVerification` 是同一種形狀：
// **把「能不能做」寫成一個純值判定，讓它不可能被忘記。**
//
// ## 為什麼「沒有輔助使用權限就必須拒絕」是硬規則
//
// 沒有 Accessibility 權限時，`CGEvent.post` **不會失敗、不會丟錯、不會回傳任何訊號
// ——它就是靜默地什麼都不做**。如果這裡不擋，整條鏈會表現成：使用者在 HUD 按了「執行」、
// 稽核寫下 `executed`、HUD 顯示「已執行」，而畫面上什麼都沒發生。
//
// 那正是這個專案從第一天就在防的東西（同一個理由讓 `.notWired` 一定要 throw、
// 讓「已執行」不能只看 `didExecute`）。**做不到的時候要大聲說做不到。**
public enum UIActionGate {

    public enum Decision: Equatable {
        case perform
        case refuse(String)
    }

    /// 這個動作是不是走 UI 路徑（而不是沙箱化的 shell 路徑）。
    public static func isUIAction(_ kind: ProposedAction.Kind) -> Bool {
        switch kind {
        case .screenshot, .click, .typeText, .keypress, .scroll: return true
        case .shell, .readFile, .writeFile, .outboundComms: return false
        }
    }

    /// 能不能真的送出這個 UI 動作。
    ///
    /// - Parameters:
    ///   - accessibilityTrusted: `AXIsProcessTrusted()`。**false 一定拒絕**，見型別註解。
    ///   - canPerform: 執行能力旗標（`UIActionPerformer.willPerformUIActions`）。
    ///     與 `ExecutorService.willExecuteActions` 同一種寫法：一個事實，不是一個開關。
    public static func decide(kind: ProposedAction.Kind,
                              accessibilityTrusted: Bool,
                              canPerform: Bool) -> Decision {
        guard isUIAction(kind) else {
            return .refuse("不是 UI 動作，不該走這條路徑（\(kind.summary)）")
        }
        // 截圖刻意不支援：它是**給模型看的**，該由擷取管線產生並隨請求出境，
        // 而出境要過 PII 遮罩與 PIPL 硬牆。在這裡偷偷截一張繞過那道閘門，
        // 是把整個出境設計拿掉——而且是靜默拿掉。
        if case .screenshot = kind {
            return .refuse("截圖不走 UI 執行端：它要經出境閘門（PII 遮罩 + PIPL），由擷取管線提供")
        }
        guard accessibilityTrusted else {
            return .refuse("缺少輔助使用權限——CGEvent 會靜默失敗，寧可明說做不到")
        }
        guard canPerform else {
            return .refuse("UI 執行能力尚未啟用（backlog step 53.6-C）")
        }
        return .perform
    }
}
