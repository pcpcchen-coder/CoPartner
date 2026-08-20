import Foundation
import CoPartnerCore
import ActionExecutor

// XPC service 端的實作（🔒 真機膠水，CI 只保證編譯）。
//
// **第 ① 段的全部工作就是：收到、解得開、回一個誠實的答案。**
// 這個檔裡刻意沒有任何執行程式碼——沒有 posix_spawn、沒有 Process、沒有 sandbox-exec。
// 不是「有能力但先關著」，是**根本沒有那個能力**。
//
// 這樣排的理由：endpoint 在第 ② 段補上呼叫者驗簽之前是誰都連得上的。
// 先讓它無害、再讓它有能力，中間任何一刻出錯都不會變成「誰都能叫它執行東西」。
final class ExecutorService: NSObject, ExecutorXPCProtocol {

    /// service 目前**有沒有執行能力**。
    ///
    /// 這不是一個開關，是一個事實的陳述——`main.swift` 拿它去餵
    /// `CallerVerification.decide`，所以翻成 true 的那一刻，
    /// 未驗證的連線會**自動**開始被拒，不需要有人記得回來改別的地方。
    ///
    /// **2026-08-20（step 53.5）：翻成 true。** 這一行單獨成為一個改動，
    /// 因為翻開執行能力若混在一大包程式碼裡，沒有人（包括作者）能真的審完。
    /// 翻開前的門禁清單見 `docs/planning/session-handoff.md` §7.6.5，當時已全數打勾：
    /// 雙向驗簽真機確認、sbpl profile 成對驗證 8 項全綠、路徑跳脫與符號連結解析、
    /// 乾跑報告逐項核對過 argv／profile／環境變數。
    ///
    /// 翻開後的能力範圍**遠比「能執行指令」窄**：只有 shell、只有本地固定表裡的
    /// 七個唯讀工具、只能寫沙箱工作目錄、斷網、家目錄關閉、秘密路徑另外 deny，
    /// 而且每個動作仍需經本地風險分級與 HUD 人工確認。
    static let willExecuteActions = true

    /// 呼叫者驗證狀態，由 `main.swift` 在啟動時決定後注入。
    private let callerVerification: CallerVerification.Mode

    init(callerVerification: CallerVerification.Mode) {
        self.callerVerification = callerVerification
    }

    func perform(requestJSON: Data, withReply reply: @escaping (Data?) -> Void) {
        let outcome: ExecutionOutcome
        do {
            let request = try ExecutionWire.decodeRequest(requestJSON)
            outcome = handle(request)
        } catch {
            // 解不開就明說解不開，不猜對方想幹嘛。
            outcome = .rejected(reason: "無法解碼請求：\(error)")
        }
        reply(try? ExecutionWire.encode(outcome))
    }

    private func handle(_ request: ExecutionRequest) -> ExecutionOutcome {
        switch request.kind {
        case .selfTest:
            let enforced: Bool
            if case .enforced = callerVerification { enforced = true } else { enforced = false }
            return .diagnostics(SelfTestReport(
                servicePID: ProcessInfo.processInfo.processIdentifier,
                serviceEUID: geteuid(),
                serviceBundleID: Bundle.main.bundleIdentifier ?? "(未知)",
                willExecuteActions: Self.willExecuteActions,
                verifiesCallerSignature: enforced,
                callerVerificationDetail: CallerVerification.describe(callerVerification)))

        case let .shell(argv, workspace):
            // ⬇️ step 53.5 起這個 guard 會放行。留著不是裝飾——它讓「有沒有執行能力」
            //    始終是一個可以在一行內翻回去的事實，出事時的第一動作就是把它翻回 false。
            guard Self.willExecuteActions else {
                return .acknowledgedNotExecuted(
                    detail: "service 尚未啟用執行能力（backlog step 53.5）")
            }
            return execute(argv: argv, workspace: workspace)

        case let .dryRun(argv, workspace):
            // ⚠️ **這個分支裡沒有任何 spawn 呼叫**——不是有但關著，是根本沒有。
            // 乾跑的價值在於「保證什麼都不會發生」，而那個保證應該來自程式碼的形狀。
            return .dryRun(dryRun(argv: argv, workspace: workspace))

        case .readFile, .writeFile:
            // **刻意不支援。** service 若直接讀寫檔案就完全繞過沙箱——
            // 那等於把 profile 的意義拿掉，而且是靜默拿掉：功能會正常運作，
            // 只是不再有任何限制。要沙箱化檔案動作得另外設計，不該混在
            // 「第一次真的執行」這一段裡。
            return .rejected(reason: "檔案動作尚未接線：直接讀寫會繞過沙箱，需獨立設計")
        }
    }

    /// 乾跑：跟 `execute` 走**完全相同**的建構順序，只是最後不 spawn。
    ///
    /// 刻意共用 `SandboxWorkspace.permitsExecuting` 與 `SbplProfileBuilder`——
    /// 乾跑若自己組一份「長得很像」的東西，它證明的就只是那份仿製品，
    /// 而真正會跑的那份仍然沒被看過。
    private func dryRun(argv: [String], workspace: SandboxWorkspace) -> DryRunReport {
        guard workspace.permitsExecuting(argv) else {
            return DryRunReport(allowedByAllowlist: false,
                                rejectionReason: "命令不在 exec 白名單內：\(argv.first ?? "(空)")",
                                spawnArguments: [], profile: "", environment: [])
        }
        let profile: String
        do {
            profile = try SbplProfileBuilder().profile(
                execAllowlist: workspace.execAllowlist,
                workspace: workspace.root,
                deniedSubpaths: workspace.deniedSubpaths,
                closedRoots: workspace.closedRoots)
        } catch {
            return DryRunReport(allowedByAllowlist: true,
                                rejectionReason: "無法產生 sandbox profile：\(error)",
                                spawnArguments: [], profile: "", environment: [])
        }
        // 目錄取自 `workspace.profileDirectory`（與真執行同一個來源），
        // 只有檔名用佔位符——真跑時那是每次新生的 UUID，乾跑要看的是路徑的**位置**，
        // 不是那個隨機字尾。
        let placeholder = (workspace.profileDirectory as NSString)
            .appendingPathComponent(".copartner-sandbox-<每次新生>.sb")
        let arguments = (try? SandboxedCommand(argv: argv, profilePath: placeholder,
                                               timeout: .seconds(30)).spawnArguments) ?? []
        return DryRunReport(allowedByAllowlist: true, rejectionReason: nil,
                            spawnArguments: arguments, profile: profile,
                            environment: SandboxedCommand.minimalEnvironment(home: workspace.root))
    }

    /// 真的執行（🔒 第 53.5 段開啟前不會被呼叫）。
    private func execute(argv: [String], workspace: SandboxWorkspace) -> ExecutionOutcome {
        // 第二道 exec 白名單檢查。sbpl 本身也會擋，但兩道的失敗模式不同：
        // profile 若因路徑寫錯而整條規則不匹配（真機踩過），沙箱可能放行；
        // 這裡是純值比對，不受路徑解析影響。
        guard workspace.permitsExecuting(argv) else {
            return .rejected(reason: "命令不在 exec 白名單內：\(argv.first ?? "(空)")")
        }
        let profile: String
        do {
            profile = try SbplProfileBuilder().profile(
                execAllowlist: workspace.execAllowlist,
                workspace: workspace.root,
                deniedSubpaths: workspace.deniedSubpaths,
                closedRoots: workspace.closedRoots)
        } catch {
            // profile 產不出來就**不執行**。「產不出來所以不套沙箱」是絕對不可以的退路。
            return .rejected(reason: "無法產生 sandbox profile：\(error)")
        }
        do {
            let output = try SandboxedCommandRunner().run(
                argv: argv, profile: profile,
                workspace: workspace, timeout: .seconds(30))
            return .executed(ExecutionReport(
                disposition: String(describing: output.disposition),
                didExecute: output.disposition.didExecute,
                stdout: output.stdout, stderr: output.stderr))
        } catch {
            return .rejected(reason: "執行失敗：\(error)")
        }
    }
}
