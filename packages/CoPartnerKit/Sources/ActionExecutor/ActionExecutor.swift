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
        guard clock.isCurrent(token.generation) else { throw ExecutionError.staleToken }
        guard token.actionID == action.id else { throw ExecutionError.tokenActionMismatch }
        guard policy.allows(action.kind) else {
            throw ExecutionError.toolNotAllowed(action.kind.summary)
        }
        if let path = Self.pathTouched(action.kind), !allowlist.permits(path) {
            throw ExecutionError.pathOutsideAllowlist(path)
        }
        switch limiter.record(action.kind.summary, at: now) {
        case .rateLimited: throw ExecutionError.rateLimited
        case .loopDetected: throw ExecutionError.loopDetected
        case .allow: break
        }
        // 稽核分成「嘗試」與「結果」兩筆（I9）。
        // 以前只記一筆 "execute …"，在 performer 為 nil 時就已經略嫌含糊；
        // step 55 ① 接上 XPC 之後更不能這樣寫——service 現在會例行地回「收到但沒做」，
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
