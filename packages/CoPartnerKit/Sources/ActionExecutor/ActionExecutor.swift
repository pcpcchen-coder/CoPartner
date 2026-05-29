import Foundation
import CoPartnerCore
// 設計：docs/design/v1_full-design.md §H（沙箱與動作執行）
// TODO: sandboxed XPC service；風險分級 Low/Medium/High
// TODO: 危險指令偵測（rm -rf / sudo / git push -f …）；高風險強制 explicit confirm
// TODO: Undo stack（APFS localsnapshot / git stash / AX tree snapshot）

public actor ActionExecutor {
    public enum Risk: Sendable { case low, medium, high }
    public init() {}
    public func execute(toolName: String, input: [String: String], risk: Risk) async throws { /* TODO */ }
}
