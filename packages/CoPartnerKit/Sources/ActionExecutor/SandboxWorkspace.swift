import Foundation
// 設計：sandbox-threat-model.md T3/T4 + B4。第 53.4 段的純值部分。
//
// 沙箱 profile 要用的三個參數：工作目錄、exec 白名單、拒絕子路徑。
//
// ⚠️ **這三個都不可以來自模型。** 這是整個沙箱有沒有意義的分水嶺：
// 如果 exec 白名單能被提議影響，模型只要把 `/bin/sh` 加進去，deny-default 就形同虛設。
// 所以白名單是**本地固定表**，contract 的工具名稱只能從表裡「挑」，不能「加」。
//
// contract 的 `allowedTools` 本身來自 `ContextEnvelope`，是主 app 組的、不是模型回的——
// 但即使如此也只當「挑選鍵」用，不當路徑用。多一層是因為這條錯了就沒有第二道防線。

public struct SandboxWorkspace: Sendable, Equatable, Codable {
    /// 沙箱內唯一可寫的目錄。
    public let root: String
    /// 可執行的二進位，**絕對路徑**。
    public let execAllowlist: [String]
    /// 即使在 root 底下也要拒絕的子路徑（秘密目錄）。
    public let deniedSubpaths: [String]
    /// 在工作目錄規則**之前**整片關掉的區域（通常是家目錄）。
    ///
    /// 存在的理由：全域 `(allow file-read-metadata)` 是為了路徑解析而放寬的，
    /// 但它跟白名單裡的 `find` / `grep` 相乘之後，語意就從「偶爾解析一個路徑」
    /// 變成「**可以掃整台機器**」——`find ~ -name "*.key"` 列得出來。
    /// 那是完全不同的量級，真機乾跑報告才看出來。
    public let closedRoots: [String]

    public init(root: String, execAllowlist: [String], deniedSubpaths: [String],
                closedRoots: [String] = []) {
        self.root = root
        self.execAllowlist = execAllowlist
        self.deniedSubpaths = deniedSubpaths
        self.closedRoots = closedRoots
    }

    /// 工具名稱 → 允許的二進位。**寫死在原始碼裡，這是刻意的。**
    ///
    /// 每加一個工具都是一次安全決定，應該在 code review 裡看得見，
    /// 而不是變成某個設定檔裡的一行、或更糟——某個提議裡的一個欄位。
    ///
    /// 目前只有 `bash` 一類，且刻意**不含 shell 本身**：`ProposedAction` 給的是 argv，
    /// executor 直接 spawn 那個二進位，中間沒有 shell，也就不需要 `/bin/sh` 在白名單裡。
    /// 放 `/bin/sh` 進來等於把 I4（無 shell 字串通道）在執行端還回去。
    static let toolBinaries: [String: [String]] = [
        "bash": ["/bin/cat", "/bin/ls", "/usr/bin/head", "/usr/bin/tail",
                 "/usr/bin/wc", "/usr/bin/grep", "/usr/bin/find"],
    ]

    /// 依 contract 允許的工具組出工作區。
    ///
    /// 未知的工具名稱**直接忽略**（而非放行）：白名單的預設值是「空的」，
    /// 不是「全部」。空白名單的後果是什麼都不能執行——那是安全的失敗方向。
    public static func forContract(allowedTools: [String], root: String,
                                   deniedSubpaths: [String] = [],
                                   closedRoots: [String] = []) -> SandboxWorkspace {
        var binaries: [String] = []
        for tool in allowedTools {
            // contract 可能寫成 "bash(sandboxed)"，取括號前的基底名。
            let base = tool.split(separator: "(").first.map(String.init) ?? tool
            if let known = toolBinaries[base] { binaries.append(contentsOf: known) }
        }
        return SandboxWorkspace(root: root,
                                execAllowlist: Array(Set(binaries)).sorted(),
                                deniedSubpaths: deniedSubpaths,
                                closedRoots: closedRoots)
    }

    /// sbpl profile 檔要放的目錄——**刻意在工作目錄之外**。
    ///
    /// 工作目錄是沙箱唯一可寫的地方，profile 放在裡面的話，被關住的命令
    /// 讀得到也寫得到它——等於把「哪些路徑被視為秘密」的地圖交給它。
    /// （真機乾跑報告揪出來的。）
    ///
    /// 這是安全的：`sandbox-exec` 在**套用沙箱之前**讀 profile，
    /// 那個檔從來不需要在沙箱可及範圍內。
    ///
    /// ⚠️ **放在這裡是因為要有單一事實來源。** 真執行與乾跑各自算一次的話，
    /// 兩邊會漂——而乾跑一旦報告了跟實際不同的路徑，它就從證據變成誤導。
    /// 這個坑真的踩到了：runner 改了、乾跑的佔位路徑沒跟上。
    public var profileDirectory: String {
        (root as NSString).deletingLastPathComponent
    }

    /// 這個 argv 的第一個元素在白名單裡嗎。
    ///
    /// sbpl 本身也會擋，這是**第二道**——兩道的失敗模式不同：
    /// profile 若因為某個路徑寫錯而整條規則不匹配（真機踩過），沙箱可能放行；
    /// 這裡是純值比對，不受路徑解析影響。
    public func permitsExecuting(_ argv: [String]) -> Bool {
        guard let command = argv.first else { return false }
        return execAllowlist.contains(command)
    }
}

extension SandboxedCommand {
    /// 沙箱內的環境變數。
    ///
    /// **不繼承父程序的環境**（威脅模型 T3 的 env 清洗）。繼承的話，
    /// `DYLD_INSERT_LIBRARIES`、`PATH`、各種 token 都會跟著進沙箱——
    /// 前兩者能改變「實際執行到什麼」，最後一種是直接把憑證遞進去。
    ///
    /// 只給最小的一組，而且 `PATH` 刻意是空的：argv[0] 一律絕對路徑，
    /// 有 `PATH` 只會讓「相對路徑也能跑」這件事悄悄變成可能。
    public static func minimalEnvironment(home: String) -> [String] {
        ["PATH=", "HOME=\(home)", "TMPDIR=\(home)", "LC_ALL=C"]
    }
}
