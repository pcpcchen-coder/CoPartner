import XCTest
import ScriptNarrator

/// L0 PII 遮罩（docs/privacy/data-classification.md + v2.1 §6）。隱私關鍵路徑。
final class PIIMaskerTests: XCTestCase {
    func testDetectsTaiwanID() {
        XCTAssertTrue(PIIMasker.detect("A123456789").contains(.taiwanID))
        XCTAssertTrue(PIIMasker.containsPII("身分證 A123456789 保密"))
    }

    func testDetectsTaiwanPhone() {
        XCTAssertTrue(PIIMasker.detect("0912345678").contains(.taiwanPhone))
    }

    func testDetectsChinaID() {
        XCTAssertTrue(PIIMasker.detect("11010519491231002X").contains(.chinaID))
    }

    func testDetectsCreditCardContiguousAndGrouped() {
        XCTAssertTrue(PIIMasker.detect("4111111111111111").contains(.creditCard))       // 16 位連號
        XCTAssertTrue(PIIMasker.detect("4111 1111 1111 1111").contains(.creditCard))    // 分組
    }

    func testOrdinaryTextHasNoFalsePositive() {
        XCTAssertFalse(PIIMasker.containsPII("WebSocket disconnect code 1006, retrying in 500ms"))
    }

    func testRedactRemovesPIIButKeepsContext() {
        let out = PIIMasker.redact("打給 0912345678 或身分證 A123456789")
        XCTAssertFalse(out.contains("0912345678"), out)
        XCTAssertFalse(out.contains("A123456789"), out)
        XCTAssertTrue(out.contains("打給"), out)          // 非 PII 脈絡保留
        XCTAssertTrue(out.contains("【已遮罩】"), out)
    }

    func testPastePreviewMasksCardNumber() {
        let (chars, preview) = PIIMasker.pastePreview("4111 1111 1111 1111")
        XCTAssertEqual(chars, 19)                          // 原始長度（含空格）仍記錄
        XCTAssertEqual(preview, "[貼上疑似卡號，已遮罩]")
    }

    func testPastePreviewTruncatesLongNonPII() {
        let (chars, preview) = PIIMasker.pastePreview(String(repeating: "x", count: 100), maxPreview: 30)
        XCTAssertEqual(chars, 100)
        XCTAssertEqual(preview, String(repeating: "x", count: 30) + "…")
    }

    func testPastePreviewShortNonPIIUnchanged() {
        let (chars, preview) = PIIMasker.pastePreview("hello world")
        XCTAssertEqual(chars, 11)
        XCTAssertEqual(preview, "hello world")
    }

    func testSecureFieldPlaceholder() {
        XCTAssertEqual(PIIMasker.secureFieldPlaceholder, "[在密碼欄輸入]")
    }
}
