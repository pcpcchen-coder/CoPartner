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
    case notWired                         // 真執行 🔒 step 53
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
        auditLog.append("execute \(action.kind.summary)")
        guard let performer else { throw ExecutionError.notWired }
        try await performer(action)
    }

    static func pathTouched(_ kind: ProposedAction.Kind) -> String? {
        switch kind {
        case let .readFile(path): return path
        case let .writeFile(path, _): return path
        default: return nil
        }
    }
}
