import Foundation
import Security
import ActionExecutor

// 由**這份組建自己的簽章**推導出「對方必須長什麼樣」的 code-signing requirement
// （威脅模型 T7）。主 app 與 XPC service 共用這個檔，兩邊互相驗。
//
// 為什麼從自己推導、而不是把 Team ID 寫死在原始碼：
// 寫死的話換簽章身分就會在執行期無聲失敗，而且原始碼裡多一個要同步維護的常數。
// 從自己推導的語意是「呼叫者必須跟我是同一個開發者簽的、而且 bundle id 是指定的那個」。
//
// ⚠️ 開發用的 ad-hoc 組建**沒有 Team ID**，requirement 組不出來。
// 那不是「驗證失敗」而是「沒有東西可以拿來驗」——回 `.unavailable`，
// 由 `CallerVerification` 決定該怎麼辦（沒有驗證就不可以有執行能力）。
enum CodeSigningIdentity {

    /// 主 app 的 bundle id。**必須與 project.yml 的 bundleIdPrefix + target 名一致。**
    /// 對不上時 requirement 會永遠不符 → 連線被拒；自檢報告會把它印出來供比對。
    static let mainAppBundleID = "com.pcpcchen.copartner.CoPartner"

    /// 組出「對方必須是 bundle id 為 `identifier`、且與本組建同一個 Team 簽的」這條 requirement。
    static func requirement(forBundleIdentifier identifier: String) -> CallerVerification.Mode {
        guard let info = selfSigningInformation() else {
            return .unavailable(reason: "讀不到本組建的簽章資訊")
        }
        guard let team = info[kSecCodeInfoTeamIdentifier as String] as? String,
              !team.isEmpty else {
            return .unavailable(reason: "此組建無 Team ID（ad-hoc / 本機開發簽章）")
        }
        return .enforced(requirement:
            "identifier \"\(identifier)\" and anchor apple generic "
            + "and certificate leaf[subject.OU] = \"\(team)\"")
    }

    /// 讀自己的簽章資訊。任何一步失敗都回 nil——**不猜、不退而求其次**，
    /// 因為「猜出來的身分」拿去當安全判斷的依據比沒有更糟。
    private static func selfSigningInformation() -> [String: Any]? {
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode else { return nil }
        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
              let dictionary = information as? [String: Any] else { return nil }
        return dictionary
    }
}
