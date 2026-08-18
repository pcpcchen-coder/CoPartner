import Foundation
import CoPartnerCore
import ActionExecutor

// 主 app 這一側的 XPC 客戶端（🔒 真機膠水，CI 只保證編譯）。
//
// 職責只有兩件：把請求送出去、把回覆**誠實**轉成結果。
// 「誠實」在這裡是具體的要求而非形容詞——service 回「收到但沒做」時，
// 這裡必須 throw。回成功的話 HUD 會顯示「已執行」，而後面每一段驗收都會建立在
// 一個假的成功上，那比沒接還糟。
@MainActor
final class XPCActionPerformer {

    /// 一次 XPC 往返可能的收場。
    enum Failure: Error {
        case cannotConnect(String)
        case badReply(String)
    }

    /// 執行一個已核准的動作。
    ///
    /// 第 ① 段的正常結果是 **throw `.notWired`**——service 收得到、解得開、但不執行。
    /// 這是預期行為，不是錯誤。
    func perform(_ action: ProposedAction, generation: Int) async throws {
        let request: ExecutionRequest
        do {
            request = try ExecutionRequest.from(action: action, generation: generation)
        } catch ExecutionWireError.notSandboxable(let summary) {
            // UI 類動作不走沙箱路徑（威脅模型 R2），該由主程序內的 AX/CGEvent 執行（🔒 未接）。
            throw ExecutionError.notSandboxable(summary)
        }

        switch try await send(request) {
        case .acknowledgedNotExecuted:
            throw ExecutionError.notWired
        case .rejected(let reason):
            throw ExecutionError.xpcUnavailable("service 拒收：\(reason)")
        case .diagnostics:
            // 送動作卻收到自檢報告 = 協定對不上，不可當成成功。
            throw ExecutionError.xpcUnavailable("回覆型別不符（收到自檢報告）")
        }
    }

    /// 除錯自檢：證明 service 真的活著、而且是**另一個程序**。
    /// 真雲端傳輸接上之前，這是唯一能驗證這條線的方式。
    func selfTest() async throws -> SelfTestReport {
        switch try await send(.selfTest()) {
        case .diagnostics(let report): return report
        case .acknowledgedNotExecuted(let detail): throw Failure.badReply(detail)
        case .rejected(let reason): throw Failure.badReply(reason)
        }
    }

    // MARK: - 連線

    /// 每次呼叫開一條新連線並用完就收。
    ///
    /// 不留長連線是刻意的：長連線要自己處理中斷後重連、以及「上一次 handoff 的連線
    /// 殘留到下一次」的狀態問題。骨架階段沒有效能壓力，換取的是沒有殘留狀態。
    private func send(_ request: ExecutionRequest) async throws -> ExecutionOutcome {
        let payload = try ExecutionWire.encode(request)
        let connection = NSXPCConnection(serviceName: ExecutorXPCService.name)
        connection.remoteObjectInterface = NSXPCInterface(with: ExecutorXPCProtocol.self)
        // 反向也驗一次：確認接電話的真的是我們自己簽的那個 service。
        // 單向驗證只擋得住「假的呼叫者」，擋不住「假的 service」——
        // 而後者拿得到的是我們要執行什麼，同樣是資訊外洩。
        if case .enforced(let requirement) =
            CodeSigningIdentity.requirement(forBundleIdentifier: ExecutorXPCService.name) {
            connection.setCodeSigningRequirement(requirement)
        }
        defer { connection.invalidate() }

        let replyData: Data = try await withCheckedThrowingContinuation { continuation in
            // ⚠️ reply、錯誤處理器、中斷、失效**四條路都可能觸發**，而
            // CheckedContinuation 重複 resume 會直接 crash。用 box 保證只 resume 一次。
            // （同 AppCoordinator.resolveDecision 踩過的那個坑。）
            let box = ContinuationBox(continuation)
            connection.interruptionHandler = { box.fail(Failure.cannotConnect("連線中斷（service 可能崩潰）")) }
            connection.invalidationHandler = { box.fail(Failure.cannotConnect("連線失效（找不到 service？）")) }
            connection.resume()

            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                box.fail(Failure.cannotConnect(error.localizedDescription))
            }
            guard let service = proxy as? ExecutorXPCProtocol else {
                box.fail(Failure.badReply("proxy 不符合協定"))
                return
            }
            service.perform(requestJSON: payload) { data in
                guard let data else { return box.fail(Failure.badReply("service 回了空資料")) }
                box.succeed(data)
            }
        }
        do {
            return try ExecutionWire.decodeOutcome(replyData)
        } catch {
            throw Failure.badReply("回覆無法解碼：\(error)")
        }
    }
}

/// 保證 continuation 只被 resume 一次。
///
/// XPC 的回呼在任意佇列上進來，而 reply 與中斷處理器可能競爭——
/// 重複 resume 不是回錯值，是直接 crash。
private final class ContinuationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, Error>?

    init(_ continuation: CheckedContinuation<Data, Error>) {
        self.continuation = continuation
    }

    func succeed(_ data: Data) { take()?.resume(returning: data) }
    func fail(_ error: Error) { take()?.resume(throwing: error) }

    private func take() -> CheckedContinuation<Data, Error>? {
        lock.lock(); defer { lock.unlock() }
        let c = continuation
        continuation = nil
        return c
    }
}
