import Foundation
import CoPartnerCore
// 設計：sandbox-threat-model.md T4（越權）。對照 TakeoverContract.allowedTools 硬擋：
// 提議用了 contract 沒授權的工具類別 → 執行前拒絕，與模型的說法無關。

public struct SandboxPolicy: Sendable {
    public let allowedTools: Set<String>

    public init(allowedTools: [String]) {
        self.allowedTools = Set(allowedTools)
    }

    public static func from(contract: TakeoverContract) -> SandboxPolicy {
        SandboxPolicy(allowedTools: contract.allowedTools)
    }

    public func allows(_ kind: ProposedAction.Kind) -> Bool {
        switch kind {
        case .screenshot, .click, .typeText, .keypress, .scroll:
            return has("computer")
        case .shell:
            return has("bash")                     // 含 "bash(sandboxed)"
        case .readFile, .writeFile:
            return has("text_editor")
        case .outboundComms:
            return has("outbound_comms")           // 預設 allowedTools 永遠沒有 → 預設拒（T4/T5）
        }
    }

    private func has(_ name: String) -> Bool {
        allowedTools.contains { $0 == name || $0.hasPrefix(name + "(") }
    }
}
