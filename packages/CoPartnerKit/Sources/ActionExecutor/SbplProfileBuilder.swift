import Foundation
// 設計：sandbox-threat-model.md §6（sbpl profile 草稿方向）+ B4。deny-default、network 全拒（T5）、
// exec 白名單逐工具開、寫入限工作目錄、秘密路徑加倍拒。此檔只產 profile 字串（CI 可測）；
// 真 sandbox-exec / posix_spawn 套用 🔒 step 53。⚠️ sandbox-exec 半棄用——53 先驗可用性，備援見威脅模型 §6。

public struct SbplProfileBuilder: Sendable {
    public init() {}

    public func profile(execAllowlist: [String], workspace: String, deniedSubpaths: [String]) -> String {
        var lines = [
            "(version 1)",
            "(deny default)",           // deny-default：一切先拒再逐項開
            "(deny network*)",          // 沙箱內一律斷網（T5 外洩）
        ]
        if !execAllowlist.isEmpty {
            let literals = execAllowlist.map { "(literal \"\($0)\")" }.joined(separator: " ")
            lines.append("(allow process-exec \(literals))")
        }
        lines.append("(allow file-read* (subpath \"\(workspace)\"))")
        lines.append("(allow file-write* (subpath \"\(workspace)\"))")
        for denied in deniedSubpaths {
            lines.append("(deny file-read* (subpath \"\(denied)\"))")
            lines.append("(deny file-write* (subpath \"\(denied)\"))")
        }
        return lines.joined(separator: "\n")
    }
}
