import Foundation
import CoPartnerCore
// 設計：sandbox-threat-model.md B3/B4。執行閘門與執行器同模組：
// `execute` 需要 ApprovalToken（只有 TakeoverSessionModel 能鑄造，I1），依序驗
// 世代（I7）→ token-動作綁定 → contract 工具白名單（T4）→ 路徑白名單（I5）→ 速率/迴圈（I8），
// 全過才執行並落稽核（I9）。真執行（XPC service + code-signing 驗證 + sandbox-exec / posix_spawn
// argv 直呼無 shell）🔒 step 53——預設 performer 為 nil，此時 throw .notWired，絕不靜默假裝執行。

public enum ExecutionError: Error, Equatable {
    case staleToken                       // 世代已作廢（Stop / kill-switch 後）
    case tokenActionMismatch              // token 綁定別的動作
    case toolNotAllowed(String)           // contract allowedTools 之外（T4）
    case pathOutsideAllowlist(String)     // 路徑白名單外（I5）
    case rateLimited                      // 超過動作速率上限（I8）
    case loopDetected                     // 同一動作連續重複（I8）
    case notWired                         // service 回覆「收到但沒做」——第 ① 段骨架的預期結果
    case xpcUnavailable(String)           // 連不上 / 連線中斷 / 回覆格式不對
    case notSandboxable(String)           // UI 類動作不走沙箱路徑（R2），該在主程序內執行
    /// UI 執行端拒絕（缺輔助使用權限、能力未啟用、座標對不上、鍵按不出來…）。
    /// 與 `.notWired` 同一個理由存在：**做不到的時候要大聲說做不到**——
    /// UI 動作沒有沙箱兜底，靜默失敗會讓稽核寫下「已執行」而畫面上什麼都沒發生。
    case uiActionRefused(String)
}

public actor ActionExecutor {
    private let clock: HandoffGeneration
    private let policy: SandboxPolicy
    private let allowlist: PathAllowlist
    private var limiter: RateLimiter
    private let performer: (@Sendable (ProposedAction) async throws -> Void)?
    /// 稽核軌跡（I9）：每次 execute（通過全部檢查者）一行，human-readable。
    public private(set) var auditLog: [String] = []

    public init(clock: HandoffGeneration,
                policy: SandboxPolicy,
                allowlist: PathAllowlist,
                limiter: RateLimiter = RateLimiter(),
                performer: (@Sendable (ProposedAction) async throws -> Void)? = nil) {
        self.clock = clock
        self.policy = policy
        self.allowlist = allowlist
        self.limiter = limiter
        self.performer = performer
    }

    public func execute(_ action: ProposedAction, token: ApprovalToken, now: Date = Date()) async throws {
        // ⚠️ **被擋下來的動作也要留紀錄**（I9：「每個提議**無論核准與否**都落 audit log」）。
        //
        // 這裡原本六條拒絕路徑全都在寫任何稽核之前就 throw，於是留下零痕跡——
        // 而那六條正好是**最需要事後查得到**的情況：用了作廢的 token、token 綁錯動作、
        // 用了 contract 沒授權的工具、想碰白名單外的路徑、連發、迴圈。
        // 稽核只記成功的話，等於「一切正常」與「有人一直被擋」在紀錄上長得一樣。
        func blocked(_ reason: String) { auditLog.append("blocked \(action.kind.summary) — \(reason)") }

        guard clock.isCurrent(token.generation) else {
            blocked("token 世代已作廢（I7）"); throw ExecutionError.staleToken
        }
        guard token.actionID == action.id else {
            blocked("token 綁定的是別的動作"); throw ExecutionError.tokenActionMismatch
        }
        guard policy.allows(action.kind) else {
            blocked("contract 未授權此工具（T4）")
            throw ExecutionError.toolNotAllowed(action.kind.summary)
        }
        if let path = Self.pathTouched(action.kind), !allowlist.permits(path) {
            blocked("路徑在白名單外（I5）：\(path)")
            throw ExecutionError.pathOutsideAllowlist(path)
        }
        switch limiter.record(action.kind.summary, at: now) {
        case .rateLimited: blocked("超過速率上限（I8）"); throw ExecutionError.rateLimited
        case .loopDetected: blocked("偵測到重複迴圈（I8）"); throw ExecutionError.loopDetected
        case .allow: break
        }
        // 通過所有閘門後，稽核分成「嘗試」與「結果」兩筆（I9）。
        // 以前只記一筆 "execute …"，在 performer 為 nil 時就已經略嫌含糊；
        // step 53.1 接上 XPC 之後更不能這樣寫——service 現在會例行地回「收到但沒做」，
        // 若稽核只留一筆 "execute"，紀錄上會顯示執行過、實際上什麼都沒發生。
        auditLog.append("attempt \(action.kind.summary)")
        guard let performer else {
            auditLog.append("notExecuted \(action.kind.summary) — 執行端未接線")
            throw ExecutionError.notWired
        }
        do {
            try await performer(action)
        } catch {
            auditLog.append("notExecuted \(action.kind.summary) — \(error)")
            throw error
        }
        auditLog.append("executed \(action.kind.summary)")
    }

    static func pathTouched(_ kind: ProposedAction.Kind) -> String? {
        switch kind {
        case let .readFile(path): return path
        case let .writeFile(path, _): return path
        default: return nil
        }
    }
}
