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

    /// service 目前**有沒有執行能力**。第 ④ 段接上真執行時才會變 true。
    ///
    /// 這不是一個開關，是一個事實的陳述——`main.swift` 拿它去餵
    /// `CallerVerification.decide`，所以翻成 true 的那一刻，
    /// 未驗證的連線會**自動**開始被拒，不需要有人記得回來改別的地方。
    static let willExecuteActions = false

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
            // ⬇️ 第 53.5 段翻開 willExecuteActions 之後，這個 guard 才會放行。
            //    在那之前，下面的執行程式碼一次都不會跑。
            guard Self.willExecuteActions else {
                return .acknowledgedNotExecuted(
                    detail: "service 尚未啟用執行能力（backlog step 53.5）")
            }
            return execute(argv: argv, workspace: workspace)

        case .readFile, .writeFile:
            // **刻意不支援。** service 若直接讀寫檔案就完全繞過沙箱——
            // 那等於把 profile 的意義拿掉，而且是靜默拿掉：功能會正常運作，
            // 只是不再有任何限制。要沙箱化檔案動作得另外設計，不該混在
            // 「第一次真的執行」這一段裡。
            return .rejected(reason: "檔案動作尚未接線：直接讀寫會繞過沙箱，需獨立設計")
        }
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
                deniedSubpaths: workspace.deniedSubpaths)
        } catch {
            // profile 產不出來就**不執行**。「產不出來所以不套沙箱」是絕對不可以的退路。
            return .rejected(reason: "無法產生 sandbox profile：\(error)")
        }
        do {
            let output = try SandboxedCommandRunner().run(
                argv: argv, profile: profile,
                workspaceRoot: workspace.root, timeout: .seconds(30))
            return .executed(ExecutionReport(
                disposition: String(describing: output.disposition),
                didExecute: output.disposition.didExecute,
                stdout: output.stdout, stderr: output.stderr))
        } catch {
            return .rejected(reason: "執行失敗：\(error)")
        }
    }
}
