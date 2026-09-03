import Foundation
// 設計：Claude computer-use 的 tool_use `input`（真 JSON）→ `ProposedActionParser` 吃的 [String:String]。
//
// 為什麼需要這一層：parser 是開發期照推測的形狀寫的，與 live 契約（2026-08-16 查證）不符：
//   | parser 期望        | 真實 API                                  |
//   | x, y 兩個獨立欄位   | coordinate: [x, y] 陣列                    |
//   | dx, dy             | scroll_direction + scroll_amount           |
// 這裡把真形狀翻成 parser 的形狀，翻譯規則集中一處、純函式、CI 可測；
// parser 本身維持不動（它同時被假 transport 與測試使用）。
//
// 原則同 I4/I9：**看不懂就 throw，絕不猜**。猜一個動作出來執行，比拒絕危險得多。

public enum ComputerUseNormalizeError: Error, Equatable {
    /// action 不在支援清單（含 computer_20251124 新增但本專案還沒對應 Kind 的，如 zoom）。
    case unsupportedAction(String)
    /// 欄位缺失或型別不符。
    case malformedField(String)
    /// 帶了修飾鍵（shift/ctrl/alt/super）的點擊或捲動。
    ///
    /// **刻意拒絕而非忽略**：`ProposedAction.Kind` 目前沒有修飾鍵的表示法，
    /// 靜默丟掉會讓實際執行的動作與 Claude 提議的不同（shift+click 選一整段 ≠ 單純 click），
    /// 而 HUD 顯示的也會是錯的——違反「模型輸出是提議、使用者看到什麼就執行什麼」。
    /// 要支援得先擴充 Kind，不是在這裡吞掉。
    case unsupportedModifier(String)
}

/// 把 computer-use 的 tool_use input JSON 正規化成 parser 的扁平字串字典。
public enum ComputerUseNormalizer {

    /// scroll 方向 → dx/dy 的**慣例**（明確寫出來，別讓呼叫端猜——同 OCR bbox 原點那課）：
    /// `down` = dy 正、`up` = dy 負、`right` = dx 正、`left` = dx 負。
    /// 即「內容捲動的方向」與螢幕座標同向（y 向下為正）。
    static func scrollDelta(direction: String, amount: Int) throws -> (dx: Int, dy: Int) {
        switch direction {
        case "down":  return (0, amount)
        case "up":    return (0, -amount)
        case "right": return (amount, 0)
        case "left":  return (-amount, 0)
        default:      throw ComputerUseNormalizeError.malformedField("scroll_direction=\(direction)")
        }
    }

    /// `computer` tool 的 input JSON → parser 形狀。
    public static func normalizeComputer(_ input: [String: Any]) throws -> [String: String] {
        guard let action = input["action"] as? String else {
            throw ComputerUseNormalizeError.malformedField("action")
        }
        // 修飾鍵先擋：click/scroll 的 `text` 是修飾鍵，語意與 type/key 的 `text` 完全不同。
        if action.hasSuffix("click") || action == "scroll", let modifier = input["text"] as? String {
            throw ComputerUseNormalizeError.unsupportedModifier(modifier)
        }

        switch action {
        case "screenshot":
            return ["action": "screenshot"]

        case "left_click":
            let (x, y) = try coordinate(input)
            return ["action": "left_click", "x": String(x), "y": String(y)]

        case "type":
            guard let text = input["text"] as? String else {
                throw ComputerUseNormalizeError.malformedField("text")
            }
            return ["action": "type", "text": text]

        case "key":
            guard let text = input["text"] as? String else {
                throw ComputerUseNormalizeError.malformedField("text")
            }
            return ["action": "key", "text": text]

        case "scroll":
            guard let direction = input["scroll_direction"] as? String else {
                throw ComputerUseNormalizeError.malformedField("scroll_direction")
            }
            guard let amount = intValue(input["scroll_amount"]) else {
                throw ComputerUseNormalizeError.malformedField("scroll_amount")
            }
            let (dx, dy) = try scrollDelta(direction: direction, amount: amount)
            // 捲動也要座標。原本這裡把 `coordinate` 丟掉，事件因此落在游標當下的位置
            // ——**而那在自動化情境下是不可預測的**：模型是看著截圖決定要捲哪一塊，
            // 游標卻可能停在完全無關的地方。真機第一次驗收就栽在這裡。
            // 缺欄位一律 throw，不退回「就捲游標那裡」——那是猜，而猜出來的動作
            // 與使用者在 HUD 上核准的不是同一件事。
            let (x, y) = try coordinate(input)
            return ["action": "scroll", "x": String(x), "y": String(y),
                    "dx": String(dx), "dy": String(dy)]

        default:
            // 含 computer_20251124 的 zoom、以及 right_click / double_click / drag /
            // hold_key / wait 等——ProposedAction.Kind 還沒有對應表示法，拒絕而非硬湊。
            throw ComputerUseNormalizeError.unsupportedAction(action)
        }
    }

    /// `bash` tool 的 input JSON → parser 形狀。
    public static func normalizeBash(_ input: [String: Any]) throws -> [String: String] {
        guard let command = input["command"] as? String else {
            throw ComputerUseNormalizeError.malformedField("command")
        }
        return ["command": command]
    }

    /// text editor tool 的 input JSON → parser 形狀。
    public static func normalizeEditor(_ input: [String: Any]) throws -> [String: String] {
        guard let command = input["command"] as? String else {
            throw ComputerUseNormalizeError.malformedField("command")
        }
        var out = ["command": command]
        if let path = input["path"] as? String { out["path"] = path }
        if let fileText = input["file_text"] as? String { out["file_text"] = fileText }
        return out
    }

    /// 依 tool 名分派。tool 名用 live 契約的實際值（見 HandoffRequestBuilder 的查證註記）。
    public static func normalize(toolName: String, input: [String: Any]) throws -> [String: String] {
        switch toolName {
        case HandoffRequestBuilder.requiredToolName:            // "computer"
            return try normalizeComputer(input)
        case "bash":
            return try normalizeBash(input)
        case "str_replace_based_edit_tool", "str_replace_editor", "text_editor":
            // 現行 text_editor_20250728 的名稱是 str_replace_based_edit_tool；
            // 另兩個是舊版名，一併接受以免版本切換時靜默失效。
            return try normalizeEditor(input)
        default:
            throw ComputerUseNormalizeError.unsupportedAction("tool:\(toolName)")
        }
    }

    // MARK: - helpers

    /// `coordinate: [x, y]` → (x, y)。JSON 數字可能被解成 Int 或 Double，兩者都收。
    private static func coordinate(_ input: [String: Any]) throws -> (Int, Int) {
        guard let raw = input["coordinate"] as? [Any], raw.count == 2,
              let x = intValue(raw[0]), let y = intValue(raw[1]) else {
            throw ComputerUseNormalizeError.malformedField("coordinate")
        }
        return (x, y)
    }

    /// JSONSerialization 依數值形式回 Int 或 Double，兩種都要接。
    private static func intValue(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let d = any as? Double { return Int(d) }
        return nil
    }
}
