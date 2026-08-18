import Foundation
import CoPartnerCore
import ActionExecutor

// 主 app 這一側的 XPC 客戶端（🔒 真機膠水，CI 只保證編譯）。
//
// 職責只有兩件：把請求送出去、把回覆**誠實**轉成結果。
// 「誠實」在這裡是具體要求而非形容詞——service 回「收到但沒做」時這裡必須 throw。
// 回成功的話 HUD 會顯示「已執行」，後面每一段驗收都會建立在一個假的成功上。
//
// ⚠️ **所有 XPC 回呼都必須標 `@Sendable`**（step 55 ② dogfood 當機的成因）。
// Swift 6 會把在 `@MainActor` 環境裡寫出來、而 API 又沒標 `@Sendable` 的閉包
// **推斷成 MainActor 隔離**，並插入執行期佇列斷言。XPC 是在自己的 serial queue 上
// 呼叫 reply / interruption / error 處理器的 → 斷言失敗 → `_dispatch_assert_queue_fail`
// 直接當掉整個 app。真機上就是這樣炸的：
//     Thread 4  Queue: com.apple.NSXPCConnection…CoPartnerExecutor (serial)
//     0  _dispatch_assert_queue_fail
// 連線相關的程式碼因此整段做成 `nonisolated static`，不讓任何閉包沾到 actor 隔離。
@MainActor
final class XPCActionPerformer {

    enum Failure: Error, CustomStringConvertible {
        case cannotConnect(String)
        case badReply(String)
        /// service 的簽章與 requirement 不符——**不是連不上**，是連上了但身分不對。
        case serviceUntrusted(String)

        var description: String {
            switch self {
            case .cannotConnect(let d): return "連不上（\(d)）"
            case .badReply(let d): return "回覆有問題（\(d)）"
            case .serviceUntrusted(let d): return "service 身分驗證失敗（\(d)）"
            }
        }
    }

    /// 執行一個已核准的動作。
    /// 第 ① 段的正常結果是 throw `.notWired`——service 收得到、解得開、但不執行。
    func perform(_ action: ProposedAction, generation: Int) async throws {
        let request: ExecutionRequest
        do {
            request = try ExecutionRequest.from(action: action, generation: generation)
        } catch ExecutionWireError.notSandboxable(let summary) {
            throw ExecutionError.notSandboxable(summary)
        }

        // 真動作一律要求 service 通過驗證——寧可不執行，也不對一個身分不明的 service 下指令。
        let outcome = try await Self.exchange(request: request,
                                              serviceRequirement: Self.serviceRequirement())
        switch outcome {
        case .acknowledgedNotExecuted:
            throw ExecutionError.notWired
        case .rejected(let reason):
            throw ExecutionError.xpcUnavailable("service 拒收：\(reason)")
        case .diagnostics:
            throw ExecutionError.xpcUnavailable("回覆型別不符（收到自檢報告）")
        }
    }

    /// 自檢結果：報告 + 反向驗證（主 app 驗 service）的實際狀況。
    struct SelfTestResult {
        let report: SelfTestReport
        /// 反向驗證的結論。真機第一次跑就是**這一項**失敗（-67050），所以要單獨報。
        let serviceVerification: String
    }

    /// 除錯自檢：證明 service 活著、是另一個程序，並診斷反向驗證通不通。
    ///
    /// 刻意**試兩次**——帶 requirement 一次、不帶一次。
    /// 只試一次的話，「連不上 service」和「連得上但簽章不符」會長得一模一樣，
    /// 而這兩件事要修的東西完全不同。
    func selfTest() async throws -> SelfTestResult {
        let requirement = Self.serviceRequirement()
        var verification = "未設定（本組建無 Team ID）"

        if let requirement {
            do {
                let outcome = try await Self.exchange(request: .selfTest(),
                                                      serviceRequirement: requirement)
                return SelfTestResult(report: try Self.report(from: outcome),
                                      serviceVerification: "通過")
            } catch {
                // 帶 requirement 失敗 → 退一步用不帶的再試，才分得出是哪一種失敗。
                verification = "❌ 不符（\(error)）"
            }
        }
        let outcome = try await Self.exchange(request: .selfTest(), serviceRequirement: nil)
        return SelfTestResult(report: try Self.report(from: outcome),
                              serviceVerification: verification)
    }

    private static func report(from outcome: ExecutionOutcome) throws -> SelfTestReport {
        switch outcome {
        case .diagnostics(let report): return report
        case .acknowledgedNotExecuted(let detail): throw Failure.badReply(detail)
        case .rejected(let reason): throw Failure.badReply(reason)
        }
    }

    /// 單次 XPC 往返的等待上限。
    private static let timeoutSeconds: Double = 10

    /// 主 app 要求 service 必須是「同 Team 簽的、bundle id 為 executor」。
    /// 組不出來（ad-hoc 組建）→ nil，由呼叫端決定怎麼辦。
    private static func serviceRequirement() -> String? {
        if case .enforced(let requirement) =
            CodeSigningIdentity.requirement(forBundleIdentifier: ExecutorXPCService.name) {
            return requirement
        }
        return nil
    }

    // MARK: - 連線（nonisolated：不讓任何 XPC 回呼沾到 actor 隔離，見檔頭）

    /// 每次呼叫開一條新連線並用完就收。
    ///
    /// 不留長連線是刻意的：長連線要自己處理中斷後重連、以及「上一次 handoff 的連線
    /// 殘留到下一次」的狀態問題。骨架階段沒有效能壓力，換取的是沒有殘留狀態。
    nonisolated private static func exchange(request: ExecutionRequest,
                                             serviceRequirement: String?) async throws -> ExecutionOutcome {
        let payload = try ExecutionWire.encode(request)
        let connection = NSXPCConnection(serviceName: ExecutorXPCService.name)
        connection.remoteObjectInterface = NSXPCInterface(with: ExecutorXPCProtocol.self)
        // 反向驗證：確認接電話的真的是我們自己簽的那個 service。
        // 單向驗證只擋得住「假的呼叫者」，擋不住「假的 service」，
        // 而後者拿得到的是我們要執行什麼——同樣是外洩。
        if let serviceRequirement {
            connection.setCodeSigningRequirement(serviceRequirement)
        }
        defer { connection.invalidate() }

        let replyData: Data = try await withCheckedThrowingContinuation { continuation in
            // ⚠️ reply、錯誤處理器、中斷、失效**四條路都可能觸發**，而
            // CheckedContinuation 重複 resume 會直接 crash。用 box 保證只 resume 一次。
            let box = ContinuationBox(continuation)
            // ⏱ 逾時保險。service 若在**啟動時**就崩潰並被 launchd 反覆重啟，
            // reply、錯誤處理器、中斷處理器可能一個都不會來——真機上就這樣讓自檢
            // 永遠卡在「檢測中…」。沒有回應本身也是一種結果，必須報得出來。
            // box 保證只 resume 一次，所以這裡與正常回覆競爭是安全的。
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.timeoutSeconds) {
                box.fail(Failure.cannotConnect(
                    "逾時（\(Int(Self.timeoutSeconds)) 秒無回應——service 可能一啟動就崩潰）"))
            }
            // 每個閉包都明標 @Sendable——見檔頭，這是當機的直接修法。
            connection.interruptionHandler = { @Sendable in
                box.fail(Failure.cannotConnect("連線中斷（service 可能崩潰）"))
            }
            connection.invalidationHandler = { @Sendable in
                box.fail(Failure.cannotConnect("連線失效（找不到 service，或簽章不符被拒）"))
            }
            connection.resume()

            let proxy = connection.remoteObjectProxyWithErrorHandler { @Sendable error in
                box.fail(Failure.cannotConnect(error.localizedDescription))
            }
            guard let service = proxy as? ExecutorXPCProtocol else {
                box.fail(Failure.badReply("proxy 不符合協定"))
                return
            }
            service.perform(requestJSON: payload) { @Sendable data in
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
