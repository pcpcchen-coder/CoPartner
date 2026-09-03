import XCTest
import CoPartnerCore
import CloudRouter

/// computer-use tool_use input → parser 形狀的正規化（step 53）。
///
/// 這一層存在的理由：`ProposedActionParser` 是開發期照推測寫的，與 2026-08-16 查證的
/// live 契約不符——真 API 送 `coordinate: [x,y]` 陣列與 `scroll_direction`/`scroll_amount`，
/// parser 卻期望 `x`/`y`/`dx`/`dy`。沒有這層翻譯，真 transport 一接上就會全數 missingField。
final class ComputerUseNormalizerTests: XCTestCase {

    // MARK: - 座標陣列（真 API 形狀）

    func testLeftClickCoordinateArrayBecomesXY() throws {
        let input: [String: Any] = ["action": "left_click", "coordinate": [500, 300]]
        let out = try ComputerUseNormalizer.normalizeComputer(input)
        XCTAssertEqual(out, ["action": "left_click", "x": "500", "y": "300"])
    }

    /// JSONSerialization 依數值形式可能給 Int 或 Double，兩者都要接。
    func testCoordinateAcceptsDoubles() throws {
        let input: [String: Any] = ["action": "left_click", "coordinate": [500.0, 300.0]]
        let out = try ComputerUseNormalizer.normalizeComputer(input)
        XCTAssertEqual(out["x"], "500")
        XCTAssertEqual(out["y"], "300")
    }

    func testMalformedCoordinateThrows() {
        let cases: [[String: Any]] = [
            ["action": "left_click"],                              // 缺 coordinate
            ["action": "left_click", "coordinate": [500]],         // 只有一個值
            ["action": "left_click", "coordinate": "500,300"],     // 型別不對
        ]
        for bad in cases {
            XCTAssertThrowsError(try ComputerUseNormalizer.normalizeComputer(bad)) { e in
                XCTAssertEqual(e as? ComputerUseNormalizeError, .malformedField("coordinate"))
            }
        }
    }

    // MARK: - scroll 方向慣例

    func testScrollDirectionConvention() throws {
        // 慣例：down = dy 正、up = dy 負、right = dx 正、left = dx 負（與螢幕座標同向）
        let cases: [(String, Int, String, String)] = [
            ("down", 3, "0", "3"), ("up", 3, "0", "-3"),
            ("right", 5, "5", "0"), ("left", 5, "-5", "0"),
        ]
        for (dir, amount, dx, dy) in cases {
            let input: [String: Any] = [
                "action": "scroll", "coordinate": [500, 400],
                "scroll_direction": dir, "scroll_amount": amount,
            ]
            let out = try ComputerUseNormalizer.normalizeComputer(input)
            XCTAssertEqual(out["dx"], dx, "direction=\(dir)")
            XCTAssertEqual(out["dy"], dy, "direction=\(dir)")
            // 座標**不可以被丟掉**——見 `testScrollCoordinateIsCarriedThrough`。
            XCTAssertEqual(out["x"], "500", "direction=\(dir)")
            XCTAssertEqual(out["y"], "400", "direction=\(dir)")
        }
    }

    /// 🔑 **這條是真機第一次 UI 驗收失敗換來的。**
    ///
    /// 原本 scroll 的正規化只取 `scroll_direction` / `scroll_amount`，把 `coordinate` 丟掉。
    /// 少了座標，捲動事件只能落在**游標當下所在的位置**——而模型是看著截圖決定要捲哪一塊，
    /// 游標可能停在完全無關的地方。真機上的表現是：畫面完全沒動，而且沒有任何錯誤。
    func testScrollCoordinateIsCarriedThrough() throws {
        let input: [String: Any] = ["action": "scroll", "coordinate": [640, 360],
                                    "scroll_direction": "down", "scroll_amount": 2]
        let out = try ComputerUseNormalizer.normalizeComputer(input)
        XCTAssertEqual(out["x"], "640")
        XCTAssertEqual(out["y"], "360")
    }

    /// 缺座標時**拒絕，不退回「就捲游標那裡」**——那是猜，而猜出來的動作與使用者
    /// 在 HUD 上核准的不是同一件事（原則同檔頭：看不懂就 throw，絕不猜）。
    func testScrollWithoutCoordinateThrows() {
        let input: [String: Any] = ["action": "scroll",
                                    "scroll_direction": "down", "scroll_amount": 2]
        XCTAssertThrowsError(try ComputerUseNormalizer.normalizeComputer(input)) { error in
            XCTAssertEqual(error as? ComputerUseNormalizeError, .malformedField("coordinate"))
        }
    }

    func testUnknownScrollDirectionThrows() {
        let input: [String: Any] = [
            "action": "scroll", "scroll_direction": "sideways", "scroll_amount": 1,
        ]
        XCTAssertThrowsError(try ComputerUseNormalizer.normalizeComputer(input))
    }

    // MARK: - 修飾鍵：刻意拒絕而非忽略

    /// shift+click 會選取一整段，與單純 click 是**不同的動作**。
    /// Kind 沒有修飾鍵的表示法，靜默丟掉會讓執行的動作與 HUD 顯示的、與 Claude 提議的都不一致。
    func testModifierClickIsRejectedNotSilentlyDropped() {
        for modifier in ["shift", "ctrl", "alt", "super"] {
            let input: [String: Any] = [
                "action": "left_click", "coordinate": [500, 300], "text": modifier,
            ]
            XCTAssertThrowsError(try ComputerUseNormalizer.normalizeComputer(input)) { e in
                XCTAssertEqual(e as? ComputerUseNormalizeError, .unsupportedModifier(modifier))
            }
        }
    }

    func testModifierScrollIsRejected() {
        let input: [String: Any] = [
            "action": "scroll", "coordinate": [500, 400],
            "scroll_direction": "down", "scroll_amount": 3, "text": "shift",
        ]
        XCTAssertThrowsError(try ComputerUseNormalizer.normalizeComputer(input)) { e in
            XCTAssertEqual(e as? ComputerUseNormalizeError, .unsupportedModifier("shift"))
        }
    }

    /// 但 type / key 的 `text` 是**內容**不是修飾鍵——不可誤擋。
    func testTypeAndKeyTextIsNotTreatedAsModifier() throws {
        let typeInput: [String: Any] = ["action": "type", "text": "shift"]
        XCTAssertEqual(try ComputerUseNormalizer.normalizeComputer(typeInput),
                       ["action": "type", "text": "shift"])
        let keyInput: [String: Any] = ["action": "key", "text": "cmd+s"]
        XCTAssertEqual(try ComputerUseNormalizer.normalizeComputer(keyInput),
                       ["action": "key", "text": "cmd+s"])
    }

    // MARK: - 不支援的 action 一律 throw（不猜）

    func testUnsupportedActionsThrow() {
        // zoom 是 computer_20251124 新增；其餘是 Kind 還沒有表示法的動作。
        for action in ["zoom", "right_click", "double_click", "left_click_drag", "hold_key", "wait"] {
            let input: [String: Any] = ["action": action]
            XCTAssertThrowsError(try ComputerUseNormalizer.normalizeComputer(input),
                                 "\(action) 應被拒絕而非硬湊成別的動作") { e in
                XCTAssertEqual(e as? ComputerUseNormalizeError, .unsupportedAction(action))
            }
        }
    }

    func testScreenshotPassesThrough() throws {
        let input: [String: Any] = ["action": "screenshot"]
        XCTAssertEqual(try ComputerUseNormalizer.normalizeComputer(input), ["action": "screenshot"])
    }

    // MARK: - tool 名分派

    /// 現行 text_editor_20250728 的 name 是 str_replace_based_edit_tool——
    /// parser 原本只認舊名，真 transport 接上會整組打不中。
    func testCurrentEditorToolNameIsAccepted() throws {
        let input: [String: Any] = ["command": "view", "path": "/tmp/a.txt"]
        let out = try ComputerUseNormalizer.normalize(toolName: "str_replace_based_edit_tool", input: input)
        XCTAssertEqual(out["command"], "view")
        XCTAssertEqual(out["path"], "/tmp/a.txt")
    }

    func testComputerToolNameMatchesContract() throws {
        let input: [String: Any] = ["action": "screenshot"]
        let out = try ComputerUseNormalizer.normalize(toolName: "computer", input: input)
        XCTAssertEqual(out, ["action": "screenshot"])
    }

    func testBashCommandPassesThrough() throws {
        let input: [String: Any] = ["command": "ls -la"]
        let out = try ComputerUseNormalizer.normalize(toolName: "bash", input: input)
        XCTAssertEqual(out, ["command": "ls -la"])
    }

    func testUnknownToolThrows() {
        let input: [String: Any] = [:]
        XCTAssertThrowsError(try ComputerUseNormalizer.normalize(toolName: "some_other_tool", input: input))
    }

    // MARK: - 端到端：正規化後 parser 一定吃得下

    /// 這條是本層存在的意義——真 API 形狀經正規化後，parser 必須產出正確的 ProposedAction。
    func testNormalizedInputFeedsParserEndToEnd() throws {
        let raw: [String: Any] = ["action": "left_click", "coordinate": [120, 240]]
        let normalized = try ComputerUseNormalizer.normalize(toolName: "computer", input: raw)
        let action = try ProposedActionParser.parse(toolName: "computer", input: normalized)
        XCTAssertEqual(action.kind, .click(x: 120, y: 240))
    }

    func testNormalizedScrollFeedsParserEndToEnd() throws {
        let raw: [String: Any] = ["action": "scroll", "coordinate": [10, 20],
                                  "scroll_direction": "down", "scroll_amount": 4]
        let normalized = try ComputerUseNormalizer.normalize(toolName: "computer", input: raw)
        let action = try ProposedActionParser.parse(toolName: "computer", input: normalized)
        XCTAssertEqual(action.kind, .scroll(x: 10, y: 20, dx: 0, dy: 4))
    }
}
