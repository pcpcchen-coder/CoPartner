import Foundation
// 設計：sandbox-threat-model.md T3/I5。檔案動作路徑：**先 canonicalize（展 ~、去 ..、解 symlink）
// 再比對**白名單——symlink /tmp/x → ~/.ssh 這類逃逸在解析後現形。秘密元件（.ssh/Keychains/.env…）
// 無論落在哪都拒。真檔案系統下的 symlink 解析可測（macOS runner），完整攻防 🔒 step 53。

public struct PathAllowlist: Sendable {
    public let allowedRoots: [String]
    public let deniedComponents: [String]

    public init(allowedRoots: [String],
                deniedComponents: [String] = [".ssh", "Keychains", ".env", ".aws", ".gnupg"]) {
        self.allowedRoots = allowedRoots
        self.deniedComponents = deniedComponents
    }

    public func permits(_ path: String) -> Bool {
        let canon = Self.canonicalize(path)
        let components = canon.split(separator: "/").map(String.init)
        for denied in deniedComponents {
            if components.contains(denied) { return false }
            if let last = components.last, last.hasSuffix(denied) { return false }   // prod.env 類
        }
        return allowedRoots.contains { root in
            let r = Self.canonicalize(root)
            return canon == r || canon.hasPrefix(r + "/")
        }
    }

    /// 展 ~ → 去 . / ..（詞法）→ 解 symlink（存在的前綴元件，含 /var→/private/var）→ 再正規化。
    public static func canonicalize(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded).standardizedFileURL
        return url.resolvingSymlinksInPath().standardizedFileURL.path
    }
}
