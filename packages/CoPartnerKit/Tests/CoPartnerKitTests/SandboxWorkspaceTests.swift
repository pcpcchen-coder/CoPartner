import XCTest
import ActionExecutor

/// step 53.4：沙箱工作區的組成。
///
/// **這組測試守的是整個沙箱有沒有意義的分水嶺**：
/// exec 白名單若能被提議影響，模型只要把 `/bin/sh` 加進去，deny-default 就形同虛設。
final class SandboxWorkspaceTests: XCTestCase {

    /// 白名單只能從**本地固定表**挑，不能由外部加。
    func testAllowlistComesFromTheLocalTableOnly() {
        let ws = SandboxWorkspace.forContract(allowedTools: ["bash"], root: "/ws")
        XCTAssertFalse(ws.execAllowlist.isEmpty)
        for binary in ws.execAllowlist {
            XCTAssertTrue(binary.hasPrefix("/"), "白名單一律絕對路徑：\(binary)")
        }
    }

    /// **shell 本身永不在白名單裡。** 放它進來等於把 I4（無 shell 字串通道）
    /// 在執行端還回去——argv 已經是結構化的，中間不需要 shell。
    func testShellBinariesAreNeverAllowlisted() {
        let ws = SandboxWorkspace.forContract(allowedTools: ["bash", "bash(sandboxed)"], root: "/ws")
        for shell in ["/bin/sh", "/bin/bash", "/bin/zsh", "/usr/bin/env"] {
            XCTAssertFalse(ws.execAllowlist.contains(shell), "\(shell) 不可在白名單內")
        }
    }

    /// 未知工具**直接忽略**而不是放行——白名單的預設值是空的，不是全部。
    func testUnknownToolsYieldAnEmptyAllowlist() {
        let ws = SandboxWorkspace.forContract(allowedTools: ["computer", "text_editor", "???"],
                                              root: "/ws")
        XCTAssertTrue(ws.execAllowlist.isEmpty, "未知工具不該產生任何可執行檔")
    }

    /// 空白名單的後果是什麼都不能執行——那是安全的失敗方向。
    func testEmptyAllowlistPermitsNothing() {
        let ws = SandboxWorkspace(root: "/ws", execAllowlist: [], deniedSubpaths: [])
        XCTAssertFalse(ws.permitsExecuting(["/bin/cat"]))
        XCTAssertFalse(ws.permitsExecuting([]))
    }

    /// contract 寫成 `bash(sandboxed)` 也要對應得到。
    func testToolNameWithParenthesesResolves() {
        let ws = SandboxWorkspace.forContract(allowedTools: ["bash(sandboxed)"], root: "/ws")
        XCTAssertTrue(ws.permitsExecuting(["/bin/cat"]))
    }

    /// 同一個二進位被多個工具帶進來時不該重複。
    func testAllowlistIsDeduplicatedAndSorted() {
        let ws = SandboxWorkspace.forContract(allowedTools: ["bash", "bash"], root: "/ws")
        XCTAssertEqual(ws.execAllowlist, Array(Set(ws.execAllowlist)).sorted())
    }

    /// 白名單比對是**完全相符**，不是前綴——否則 `/bin/cat_evil` 會通過。
    func testAllowlistMatchIsExactNotPrefix() {
        let ws = SandboxWorkspace(root: "/ws", execAllowlist: ["/bin/cat"], deniedSubpaths: [])
        XCTAssertTrue(ws.permitsExecuting(["/bin/cat"]))
        XCTAssertFalse(ws.permitsExecuting(["/bin/cat_evil"]))
        XCTAssertFalse(ws.permitsExecuting(["/bin/ca"]))
    }

    // MARK: - 環境變數清洗（T3）

    /// **不繼承父程序環境**。繼承的話 DYLD_INSERT_LIBRARIES 能改變實際執行到什麼，
    /// 而各種 token 會被直接遞進沙箱。
    func testMinimalEnvironmentDoesNotLeakParentVariables() {
        let env = SandboxedCommand.minimalEnvironment(home: "/ws")
        let names = env.map { $0.split(separator: "=", maxSplits: 1).first.map(String.init) ?? "" }
        XCTAssertEqual(Set(names), ["PATH", "HOME", "TMPDIR", "LC_ALL"])
    }

    /// `PATH` 刻意是空的：argv[0] 一律絕對路徑，有 PATH 只會讓「相對路徑也能跑」
    /// 這件事悄悄變成可能。
    func testPathIsEmpty() {
        XCTAssertTrue(SandboxedCommand.minimalEnvironment(home: "/ws").contains("PATH="))
    }
}
