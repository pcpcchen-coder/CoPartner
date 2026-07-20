import Foundation
// 設計：docs/design/v2_smart-capture-engine.md §G（黑名單源頭排除）。黑名單 app（密碼管理器/銀行類）
// **連 frame 都不進** SCStream；用 includingApplications 白名單實作（避 §G 已知空陣列 bug）；
// 自身 app 恆排除（避錄製迴圈）。純決策、CI 可測；真 SCContentFilter(display:including:) 膠水 🔒 step 58。

public struct CaptureBlacklist: Sendable {
    public let blockedBundleIDs: Set<String>
    public let blockedNamePatterns: [String]
    public let ownBundleID: String

    public static let defaultBundleIDs: Set<String> = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.agilebits.onepassword4",
        "com.bitwarden.desktop", "com.lastpass.LastPass", "com.apple.keychainaccess",
    ]
    public static let defaultNamePatterns = ["bank", "banking", "密碼", "password manager", "1password", "bitwarden"]

    public init(blockedBundleIDs: Set<String> = CaptureBlacklist.defaultBundleIDs,
                blockedNamePatterns: [String] = CaptureBlacklist.defaultNamePatterns,
                ownBundleID: String) {
        self.blockedBundleIDs = blockedBundleIDs
        self.blockedNamePatterns = blockedNamePatterns
        self.ownBundleID = ownBundleID
    }

    public func isBlocked(bundleID: String?, appName: String) -> Bool {
        if let bundleID {
            if bundleID == ownBundleID { return true }              // 自身 app 恆排除（錄製迴圈）
            if blockedBundleIDs.contains(bundleID) { return true }
        }
        let lower = appName.lowercased()
        return blockedNamePatterns.contains { lower.contains($0.lowercased()) }
    }

    /// 白名單實作：allApps 減去 blocked。**空 → nil（別開 stream），永不回空陣列**（§G bug 防禦）。
    public func includeList<App>(allApps: [App],
                                 bundleID: (App) -> String?,
                                 name: (App) -> String) -> [App]? {
        let kept = allApps.filter { !isBlocked(bundleID: bundleID($0), appName: name($0)) }
        return kept.isEmpty ? nil : kept
    }
}
