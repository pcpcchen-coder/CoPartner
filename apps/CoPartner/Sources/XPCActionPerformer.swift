import Foundation
import CoPartnerCore
import ActionExecutor

// 主 app 這一側的 XPC 客戶端（🔒 真機膠水，CI 只保證編譯）。
//
// 職責只有兩件：把請求送出去、把回覆**誠實**轉成結果。
// 「誠實」在這裡是具體要求而非形容詞——service 回「收到但沒做」時這裡必須 throw。
// 回成功的話 HUD 會顯示「已執行」，後面每一段驗收都會建立在一個假的成功上。
//
// ⚠️ **所有 XPC 回呼都必須標 `@Sendable`**（step 53.2 dogfood 當機的成因）。
// Swift 6 會把在 `@MainActor` 環境裡寫出來、而 API 又沒標 `@Sendable` 的閉包
// **推斷成 MainActor 隔離**，並插入執行期佇列斷言。XPC 是在自己的 serial queue 上
// 呼叫 reply / interruption / error 處理器的 → 斷言失敗 → `_dispatch_assert_queue_fail`
// 直接當掉整個 app。真機上就是這樣炸的：
//     Thread 4  Queue: com.apple.NSXPCConnection…CoPartnerExecutor (serial)
//     0  _dispatch_assert_queue_fail
// 連線相關的程式碼因此整段做成 `nonisolated static`，不讓任何閉包沾到 actor 隔離。
/// 單次 XPC 往返的等待上限。
///
/// 放在檔案層而不是 `XPCActionPerformer` 的 static 屬性：那個型別是 `@MainActor`，
/// 它的 static 屬性也跟著被 MainActor 隔離，而逾時閉包跑在全域佇列上、
/// `exchange` 又是 `nonisolated`——從那裡讀就是跨隔離存取，Swift 6 直接擋下來。
private let xpcTimeoutSeconds: Double = 10

@MainActor
final class XPCActionPerformer {

    enum Failure: Error, CustomStringConvertible {
        case cannotConnect(String)
        case badReply(String)
        /// **還沒送出**就拒絕：驗不了 service 身分，而這是一個真動作。
        /// 與 `cannotConnect` 的差別在於「連都沒連」——這是我們自己的決定，不是對方的問題。
        case refusedToSend(String)

        var description: String {
            switch self {
            case .cannotConnect(let d): return "連不上（\(d)）"
            case .badReply(let d): return "回覆有問題（\(d)）"
            case .refusedToSend(let d): return "拒絕送出（\(d)）"
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

        // 對稱規則（與 service 端的「沒有驗證就不可以有執行能力」成對）：
        // 驗不了 service 身分就**不送真動作**。寧可不執行，也不對身分不明的對象下指令。
        let mode = CodeSigningIdentity.requirement(forBundleIdentifier: ExecutorXPCService.name)
        if case .refuse(let reason) =
            CallerVerification.decideOutbound(mode: mode, isRealAction: true) {
            throw Failure.refusedToSend(reason)
        }
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
    /// （`decideOutbound(isRealAction: false)` 允許在驗不了身分時仍進行——
    /// 送的是 `.selfTest`，協定上就不是一個動作。診斷能力不該被安全規則鎖死，
    /// 否則驗不出問題時連怎麼壞的都看不到。）
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
            // ⚠️ reply、錯誤處理器、中斷、失效、逾時**五條路都可能觸發**，各自在不同佇列上，
            // 而 CheckedContinuation 重複 resume **不是回錯值，是直接 crash**。
            // `SingleCompletion` 在 CoPartnerKit 裡，因此那個保證有 CI 的多執行緒測試撞過——
            // 這種競態靠 dogfood 幾乎抓不到，真機上只會表現成「偶爾閃退」。
            let box = SingleCompletion<Data> { continuation.resume(with: $0) }
            // ⏱ 逾時保險。service 若在**啟動時**就崩潰並被 launchd 反覆重啟，
            // reply、錯誤處理器、中斷處理器可能一個都不會來——真機上就這樣讓自檢
            // 永遠卡在「檢測中…」。沒有回應本身也是一種結果，必須報得出來。
            // box 保證只 resume 一次，所以這裡與正常回覆競爭是安全的。
            DispatchQueue.global().asyncAfter(deadline: .now() + xpcTimeoutSeconds) {
                box.fail(Failure.cannotConnect(
                    "逾時（\(Int(xpcTimeoutSeconds)) 秒無回應——service 可能一啟動就崩潰）"))
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
