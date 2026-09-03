import Foundation
import CoPartnerCore
// 設計：Claude computer-use 的 tool_use（已由 transport adapter 正規化成 [String:String]）→ ProposedAction。
// 未知 tool/action、缺欄位 → throws（**不猜**，I4/I9）。真 tool_use JSON 的正規化在 transport（🔒 step 53）。

public enum ProposedActionParseError: Error, Equatable {
    case unknownTool(String)
    case unknownAction(String)
    case missingField(String)
}

public enum ProposedActionParser {
    /// toolName + 正規化 input → ProposedAction。
    public static func parse(toolName: String, input: [String: String], rationale: String = "") throws -> ProposedAction {
        switch toolName {
        case "computer":
            return ProposedAction(kind: try computerKind(input), rationale: rationale)
        case "bash":
            // I4：bash 只轉 argv（whitespace 切），metachar 變字面 arg——executor 不經 sh -c 故無害。
            let cmd = try require(input, "command")
            return ProposedAction(kind: .shell(argv: cmd.split(separator: " ").map(String.init)), rationale: rationale)
        case "str_replace_editor", "text_editor":
            return ProposedAction(kind: try editorKind(input), rationale: rationale)
        default:
            throw ProposedActionParseError.unknownTool(toolName)
        }
    }

    private static func computerKind(_ input: [String: String]) throws -> ProposedAction.Kind {
        switch try require(input, "action") {
        case "screenshot": return .screenshot
        case "left_click", "click": return .click(x: try requireInt(input, "x"), y: try requireInt(input, "y"))
        case "type": return .typeText(try require(input, "text"))
        case "key": return .keypress(try require(input, "text"))
        case "scroll": return .scroll(x: try requireInt(input, "x"), y: try requireInt(input, "y"),
                                      dx: try requireInt(input, "dx"), dy: try requireInt(input, "dy"))
        case let other: throw ProposedActionParseError.unknownAction(other)
        }
    }

    private static func editorKind(_ input: [String: String]) throws -> ProposedAction.Kind {
        switch try require(input, "command") {
        case "view": return .readFile(path: try require(input, "path"))
        case "create": return .writeFile(path: try require(input, "path"), contents: try require(input, "file_text"))
        case let other: throw ProposedActionParseError.unknownAction(other)
        }
    }

    private static func require(_ input: [String: String], _ key: String) throws -> String {
        guard let v = input[key] else { throw ProposedActionParseError.missingField(key) }
        return v
    }
    private static func requireInt(_ input: [String: String], _ key: String) throws -> Int {
        guard let v = input[key], let n = Int(v) else { throw ProposedActionParseError.missingField(key) }
        return n
    }
}

/// 稽核（不變式 I9）：每個提議落一行 human-readable log（含 context_hash）。
/// 動作描述本體在 `ProposedAction.Kind.summary`（CoPartnerCore，與 ActionExecutor 共用）。
public enum HandoffAuditLog {
    public static func line(for action: ProposedAction, contextHash: String) -> String {
        "[handoff \(contextHash)] propose \(describe(action.kind))"
    }

    static func describe(_ kind: ProposedAction.Kind) -> String { kind.summary }
}
