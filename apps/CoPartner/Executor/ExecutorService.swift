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

        case .shell, .readFile, .writeFile:
            // 誠實回報：收到了、解得開、但**沒有執行**。
            // 主 app 端會把這個回覆轉成 throw，所以 HUD 不會顯示「已執行」。
            return .acknowledgedNotExecuted(
                detail: "XPC 骨架：service 尚未具備執行能力（第 ③④ 段）")
        }
    }
}
