import Foundation
// 設計：sandbox-threat-model.md §5 危險 pattern 清單（T1/T2/T5/T9，不變式 I3）。
// 吃結構化 argv（非自由文字；parser 已把 pipe 變字面 arg）。**保守偏殺**：
// 誤殺的代價 = 使用者多按一次確認；漏殺的代價 = 真損害。清單只增不減。

public struct DangerousCommandDetector: Sendable {
    public init() {}

    /// argv 命中危險 pattern → 回原因（給 HUD 顯示「為什麼要你確認」）；nil = 未命中。
    public func reason(argv: [String]) -> String? {
        guard let first = argv.first else { return nil }
        let cmd = (first as NSString).lastPathComponent
        let rest = Array(argv.dropFirst())

        if ["sudo", "su", "csrutil", "nvram", "shred", "osascript"].contains(cmd) {
            return "提權/系統指令 \(cmd)"
        }
        if cmd.hasPrefix("mkfs") { return "格式化指令" }

        if cmd == "rm" {
            let shortFlags = rest.filter { $0.hasPrefix("-") && !$0.hasPrefix("--") }
                .flatMap { Array($0.dropFirst()) }
            let recursive = shortFlags.contains("r") || shortFlags.contains("R") || rest.contains("--recursive")
            let force = shortFlags.contains("f") || rest.contains("--force")
            let targets = rest.filter { !$0.hasPrefix("-") }
            let rootTarget = targets.contains { ["/", "~", "/*", "~/"].contains($0) }
            if (recursive && force) || rootTarget { return "遞迴強制刪除" }
        }
        if cmd == "dd", rest.contains(where: { $0.hasPrefix("of=/dev/") }) { return "直寫裝置" }
        if cmd == "git" {
            if rest.contains("push"), rest.contains(where: { $0 == "-f" || $0 == "--force" }) { return "強制推送" }
            if rest.contains("reset"), rest.contains("--hard") { return "git 硬重置" }
            if rest.contains("clean"), rest.contains(where: { $0.hasPrefix("-") && !$0.hasPrefix("--") && $0.contains("f") }) {
                return "清除未追蹤檔"
            }
        }
        if cmd == "launchctl", rest.contains(where: { ["load", "unload", "bootstrap"].contains($0) }) {
            return "launchd 操作"
        }
        if cmd == "defaults", rest.contains("write") { return "系統偏好寫入" }
        if ["sh", "bash", "zsh"].contains(cmd), rest.contains("-c") { return "shell -c 任意字串" }
        if let pipeIdx = argv.firstIndex(of: "|"),
           argv[(pipeIdx + 1)...].contains(where: { ["sh", "bash", "zsh"].contains(($0 as NSString).lastPathComponent) }) {
            return "管線接 shell"
        }
        if argv.contains(where: { $0.contains(":(){") }) { return "fork bomb" }
        if argv.contains(where: { $0.hasPrefix(">") && $0.contains("/dev/") }) { return "重導向至裝置" }
        if argv.contains(where: { Self.touchesSecretPath($0) }) { return "涉及秘密路徑" }
        return nil
    }

    /// 秘密路徑（T5）：讀或寫都算。供 argv 與檔案動作路徑共用。
    public static func touchesSecretPath(_ s: String) -> Bool {
        let lower = s.lowercased()
        if lower.contains("/.ssh") || lower.hasPrefix("~/.ssh") { return true }
        if lower.contains("keychains") { return true }
        if lower.hasSuffix(".env") || lower.contains("/.env") { return true }
        if lower.contains("/.aws") { return true }
        if lower.hasSuffix("history") { return true }   // bash_history / zsh_history
        return false
    }
}
