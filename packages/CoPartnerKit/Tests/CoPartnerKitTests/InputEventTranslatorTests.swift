import XCTest
import ScriptNarrator

/// 輸入 → L0 事件翻譯（§2 TYPE/PASTE/SCROLL）。含密碼欄不外洩的安全性質。
final class InputEventTranslatorTests: XCTestCase {
    // MARK: SCROLL
    func testScrollVerticalDown() {
        guard case .scroll(let app, let dir, let dist)? =
                InputEventTranslator.scroll(app: "Safari", deltaX: 0, deltaY: -10) else { return XCTFail() }
        XCTAssertEqual(app, "Safari"); XCTAssertEqual(dir, .down); XCTAssertEqual(dist, 10)
    }

    func testScrollVerticalUp() {
        guard case .scroll(_, let dir, _)? =
                InputEventTranslator.scroll(app: "X", deltaX: 0, deltaY: 5) else { return XCTFail() }
        XCTAssertEqual(dir, .up)
    }

    func testScrollHorizontalWinsWhenLarger() {
        guard case .scroll(_, let dir, let dist)? =
                InputEventTranslator.scroll(app: "X", deltaX: -20, deltaY: 3) else { return XCTFail() }
        XCTAssertEqual(dir, .left); XCTAssertEqual(dist, 20)
    }

    func testNoScrollReturnsNil() {
        XCTAssertNil(InputEventTranslator.scroll(app: "X", deltaX: 0, deltaY: 0))
    }

    // MARK: TYPE
    func testTypePrintableCharacter() {
        guard case .type(let field, let text)? =
                InputEventTranslator.type(field: "AXTextArea", character: "a", isSecureField: false) else { return XCTFail() }
        XCTAssertEqual(field, "AXTextArea"); XCTAssertEqual(text, "a")
    }

    func testTypeCJKAndSpaceAreLoggable() {
        XCTAssertNotNil(InputEventTranslator.type(field: "f", character: "文", isSecureField: false))
        XCTAssertNotNil(InputEventTranslator.type(field: "f", character: " ", isSecureField: false))
    }

    func testTypeControlAndFunctionKeysSkipped() {
        XCTAssertNil(InputEventTranslator.type(field: "f", character: "\u{8}", isSecureField: false))   // backspace
        XCTAssertNil(InputEventTranslator.type(field: "f", character: "\r", isSecureField: false))      // enter
        XCTAssertNil(InputEventTranslator.type(field: "f", character: "\t", isSecureField: false))      // tab
        XCTAssertNil(InputEventTranslator.type(field: "f", character: "\u{F700}", isSecureField: false)) // 上方向鍵
    }

    func testSecureFieldNeverLogsActualCharacter() {
        guard case .type(_, let text)? =
                InputEventTranslator.type(field: "AXSecureTextField", character: "s", isSecureField: true) else { return XCTFail() }
        XCTAssertEqual(text, "[在密碼欄輸入]")
        XCTAssertFalse(text.contains("s"))   // 絕不含實際輸入
    }

    func testIsSecureDetection() {
        XCTAssertTrue(InputEventTranslator.isSecure(role: "AXSecureTextField", subrole: nil))
        XCTAssertTrue(InputEventTranslator.isSecure(role: "AXTextField", subrole: "AXSecureTextField"))
        XCTAssertFalse(InputEventTranslator.isSecure(role: "AXTextArea", subrole: nil))
    }

    // MARK: PASTE
    func testPasteMasksPII() {
        guard case .paste(let chars, let preview)? =
                InputEventTranslator.paste(clipboard: "4111 1111 1111 1111") else { return XCTFail() }
        XCTAssertEqual(chars, 19)
        XCTAssertEqual(preview, "[貼上疑似卡號，已遮罩]")
    }

    func testPasteTruncatesLongContent() {
        guard case .paste(let chars, let preview)? =
                InputEventTranslator.paste(clipboard: String(repeating: "x", count: 100), maxPreview: 30) else { return XCTFail() }
        XCTAssertEqual(chars, 100)
        XCTAssertEqual(preview, String(repeating: "x", count: 30) + "…")
    }

    func testEmptyPasteReturnsNil() {
        XCTAssertNil(InputEventTranslator.paste(clipboard: ""))
    }
}
