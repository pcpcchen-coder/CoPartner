import Foundation
import CoPartnerCore
// 設計：v1 §F（介入 HUD）+ sandbox-threat-model.md B3/T7/I1/I2/I7。
// 接手 HUD 的可測狀態機：顯示提議 → Approve/Skip/Stop → 鑄造 ApprovalToken。
// **I1 由編譯器保證**：ApprovalToken 的 init 為 internal——只有本模組（本狀態機）能鑄造，
// 模組外不存在「繞過確認直接呼叫 execute」的合法路徑。SwiftUI 浮層殼在 app（🔒 step 53 目測）。

/// 執行核准憑證。攜帶 handoff 世代號 + 綁定的動作 id；`internal` init（I1）。
public struct ApprovalToken: Sendable, Equatable {
    let generation: Int
    let actionID: UUID
    init(generation: Int, actionID: UUID) {
        self.generation = generation
        self.actionID = actionID
    }
}

/// handoff 世代時鐘：Stop / kill-switch 一撥，該世代所有 token 立即作廢（I7）。
/// 狀態機與 ActionExecutor 共用同一實例——單一權威，無兩套真相。
public final class HandoffGeneration: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    public init() {}
    /// 開新 handoff 世代。
    public func next() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
    /// 作廢目前世代（bump——既有 token 全部失配）。冪等安全。
    public func abort() { lock.lock(); defer { lock.unlock() }; value += 1 }
    public func isCurrent(_ g: Int) -> Bool { lock.lock(); defer { lock.unlock() }; return g == value }
    var current: Int { lock.lock(); defer { lock.unlock() }; return value }
}

/// 接手 HUD 狀態機（純值、決定性測試）。
public struct TakeoverSessionModel: Sendable {
    public enum HUDState: Sendable, Equatable {
        case idle
        case proposing                                     // 等雲端下一個提議
        case awaitingApproval(ProposedAction, ActionRisk)  // 顯示動作原文 + 風險，等人按
        case executing(ProposedAction)
        case done
        case aborted
    }

    public private(set) var state: HUDState = .idle
    public let policy: TakeoverContract.Policy
    public let autoBoundedCap: Int
    public let generationClock: HandoffGeneration
    private var autoApprovedCount = 0

    public init(policy: TakeoverContract.Policy,
                generationClock: HandoffGeneration = HandoffGeneration(),
                autoBoundedCap: Int = 5) {
        self.policy = policy
        self.generationClock = generationClock
        self.autoBoundedCap = autoBoundedCap
    }

    /// 熱鍵觸發、handoff 開始：開新世代、歸零 auto 計數。
    public mutating func begin() {
        _ = generationClock.next()
        autoApprovedCount = 0
        state = .proposing
    }

    /// 收到雲端提議。autoBounded 且 **low** 風險且未達上限 → 自動核（回 token）；
    /// 其餘（含所有 high——I2）→ 進 awaitingApproval 等人按。
    public mutating func receive(_ action: ProposedAction, risk: ActionRisk) -> ApprovalToken? {
        guard state == .proposing else { return nil }
        if policy == .autoBounded, risk == .low, autoApprovedCount < autoBoundedCap {
            autoApprovedCount += 1
            state = .executing(action)
            return mint(action)
        }
        state = .awaitingApproval(action, risk)
        return nil
    }

    /// 使用者按 Approve → 鑄造 token（唯一鑄造點之二；另一為 autoBounded 低風險自動核）。
    /// suggestOnly 永不執行——按了也只回 nil、前進下一提議。
    public mutating func approve() -> ApprovalToken? {
        guard case let .awaitingApproval(action, _) = state else { return nil }
        guard policy != .suggestOnly else {
            state = .proposing
            return nil
        }
        state = .executing(action)
        return mint(action)
    }

    /// 使用者按 Skip：不執行、看下一個。
    public mutating func skip() {
        guard case .awaitingApproval = state else { return }
        state = .proposing
    }

    /// 一個動作執行完 → 回 proposing 等下一提議。
    public mutating func finishExecution() {
        guard case .executing = state else { return }
        state = .proposing
    }

    /// 使用者按 Stop / kill-switch：中止並作廢整個世代的 token（I7）。
    public mutating func stop() {
        generationClock.abort()
        state = .aborted
    }

    /// handoff 正常結束。
    public mutating func complete() { state = .done }

    private func mint(_ action: ProposedAction) -> ApprovalToken {
        ApprovalToken(generation: generationClock.current, actionID: action.id)
    }
}
