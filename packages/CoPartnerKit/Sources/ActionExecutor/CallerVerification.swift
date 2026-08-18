import Foundation
// 設計：sandbox-threat-model.md T7（繞過確認閘門：另一個本地程序打 XPC）。
//
// XPC service 的 endpoint 是本機任何程序都連得到的。擋住「不是主 app 的呼叫者」
// 靠的是 code-signing requirement——但那需要**這份組建真的有簽章身分**，
// 開發用的 ad-hoc 組建沒有 Team ID，requirement 組不出來。
//
// 於是有一個很容易踩的坑：開發時驗不了 → 先放行 → 之後接上真執行 → 忘了把放行拿掉。
// 那條路的終點是「本機任何程序都能叫 CoPartner 執行指令」。
//
// 這個檔把那件事變成**結構上不可能**，而不是一條要記得的規則：
//
//     沒有呼叫者驗證 ⟹ service 不可以有執行能力
//
// 第 ④ 段把 `serviceCanExecute` 翻成 true 的那一刻，未驗證的連線自動開始被拒——
// 不需要有人記得回來改這裡。
public enum CallerVerification {

    /// 呼叫者驗證目前處於什麼狀態。
    public enum Mode: Sendable, Equatable {
        /// requirement 已交給系統強制執行（連線層就擋掉不符者）。
        case enforced(requirement: String)
        /// 組不出 requirement——例如 ad-hoc / 未簽章的開發組建沒有 Team ID。
        /// **不是**「驗證失敗」，是「沒有東西可以拿來驗」。
        case unavailable(reason: String)
    }

    public enum Decision: Sendable, Equatable {
        case accept
        case refuse(reason: String)
    }

    /// 要不要接受這條連線。
    ///
    /// `serviceCanExecute` 是 service 端「我現在有沒有執行能力」的事實，
    /// 不是一個設定選項——它會隨第 ④ 段接上真執行而變成 true。
    public static func decide(mode: Mode, serviceCanExecute: Bool) -> Decision {
        switch mode {
        case .enforced:
            // 系統已在連線層驗過 requirement，能走到這裡代表呼叫者符合。
            return .accept
        case .unavailable(let reason):
            guard serviceCanExecute else {
                // 驗不了、但 service 本來就什麼都不會做 → 放行是安全的。
                // 這正是「先讓 endpoint 無害、再讓它有能力」的分段順序所依賴的前提。
                return .accept
            }
            return .refuse(reason: "無法驗證呼叫者（\(reason)），而 service 具備執行能力——拒絕連線")
        }
    }

    /// 給人看的一行狀態，放進自檢報告。
    public static func describe(_ mode: Mode) -> String {
        switch mode {
        case .enforced(let requirement): return "已啟用：\(requirement)"
        case .unavailable(let reason): return "未啟用（\(reason)）"
        }
    }
}
