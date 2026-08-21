import XCTest
import CoPartnerCore
@testable import ActionExecutor

/// step 53.6-A：組合鍵解析與危險組合鍵分級。
///
/// 這一層要守住的性質只有一句：**HUD 上顯示的，必須就是實際會按下去的。**
/// 「認得幾個算幾個」的解析器會讓使用者核准 `⌘⇧Q`（登出）而實際送出 `⌘Q`（結束 app），
/// 或者反過來——人工確認閘門的整個價值就建立在這兩者相等上。
final class KeyChordTests: XCTestCase {

    // MARK: - 解析

    func testParsesPlusSeparatedChord() throws {
        let chord = try KeyChord.parse("cmd+shift+q")
        XCTAssertEqual(chord.modifiers, [.command, .shift])
        XCTAssertEqual(chord.key, "q")
    }

    /// 同一個組合鍵的各種寫法必須解析成**同一個值**。
    /// 不正規化的話，危險組合鍵表就得列出所有寫法，漏一種＝那個組合鍵靜默降級。
    func testAliasesAndSymbolsNormalizeToSameChord() throws {
        let expected = KeyChord(modifiers: [.command, .shift], key: "q")
        for raw in ["cmd+shift+q", "Command+Shift+Q", "⌘⇧Q", "⌘+⇧+q",
                    "meta+shift+q", "cmd-shift-q", "  cmd + shift + q  "] {
            XCTAssertEqual(try KeyChord.parse(raw), expected, "「\(raw)」應該正規化成同一個組合鍵")
        }
    }

    func testNamedKeysNormalize() throws {
        XCTAssertEqual(try KeyChord.parse("cmd+backspace").key, "delete")
        XCTAssertEqual(try KeyChord.parse("cmd+delete").key, "delete")
        XCTAssertEqual(try KeyChord.parse("esc").key, "escape")
        XCTAssertEqual(try KeyChord.parse("Escape").key, "escape")
        XCTAssertEqual(try KeyChord.parse("cmd+F5").key, "f5")
    }

    /// 分隔符本身也可能是主鍵（`⌘-` 縮小、`⌘+` 放大）。
    /// 直接 `split` 會把它們解析成「只有修飾鍵、沒有主鍵」。
    func testSeparatorCharactersCanBeTheKey() throws {
        XCTAssertEqual(try KeyChord.parse("cmd+-"), KeyChord(modifiers: [.command], key: "-"))
        XCTAssertEqual(try KeyChord.parse("cmd++"), KeyChord(modifiers: [.command], key: "+"))
    }

    // MARK: - 拒絕路徑

    /// **認不得就整個失敗**，不可以悄悄丟掉那一段。
    func testUnknownTokenThrowsInsteadOfBeingDropped() {
        XCTAssertThrowsError(try KeyChord.parse("cmd+hyper+q")) { error in
            XCTAssertEqual(error as? KeyChord.ParseError, .unknownToken("hyper"))
        }
        XCTAssertThrowsError(try KeyChord.parse("retunr")) { error in
            XCTAssertEqual(error as? KeyChord.ParseError, .unknownToken("retunr"))
        }
    }

    func testMissingOrDoubledMainKeyThrows() {
        XCTAssertThrowsError(try KeyChord.parse("cmd+")) { error in
            XCTAssertEqual(error as? KeyChord.ParseError, .malformed("cmd+"))
        }
        XCTAssertThrowsError(try KeyChord.parse("cmd")) { error in
            XCTAssertEqual(error as? KeyChord.ParseError, .malformed("cmd"))
        }
        // 按順序敲兩下 ≠ 同時按住，不可當成一個組合鍵接受。
        XCTAssertThrowsError(try KeyChord.parse("cmd+q+w")) { error in
            XCTAssertEqual(error as? KeyChord.ParseError, .malformed("cmd+q+w"))
        }
    }

    func testEmptyThrows() {
        XCTAssertThrowsError(try KeyChord.parse("   ")) { error in
            XCTAssertEqual(error as? KeyChord.ParseError, .empty)
        }
    }

    // MARK: - 正規顯示

    /// 顯示順序固定為 ⌃⌥⇧⌘，讓同一個組合鍵永遠印成同一個字串。
    func testCanonicalUsesFixedModifierOrder() throws {
        XCTAssertEqual(try KeyChord.parse("shift+ctrl+cmd+opt+a").canonical, "⌃⌥⇧⌘A")
        XCTAssertEqual(try KeyChord.parse("cmd+opt+shift+ctrl+a").canonical, "⌃⌥⇧⌘A")
    }

    // MARK: - 危險組合鍵

    func testDestructiveChordsAreRecognisedAcrossSpellings() {
        for raw in ["cmd+q", "⌘Q", "Command+Q"] {
            XCTAssertNotNil(DestructiveKeyChords.consequence(ofRaw: raw), "「\(raw)」應該被認出來")
        }
        // 清空垃圾桶的三種寫法都要認得（別名 + 符號 + backspace 同義）。
        for raw in ["cmd+shift+delete", "cmd+shift+backspace", "⌘⇧+delete"] {
            XCTAssertNotNil(DestructiveKeyChords.consequence(ofRaw: raw), "「\(raw)」應該被認出來")
        }
    }

    /// 一般組合鍵不在表上——把所有組合鍵都列成 high 等於沒有分級。
    func testOrdinaryChordsAreNotDestructive() {
        for raw in ["cmd+s", "cmd+c", "cmd+v", "cmd+z", "cmd+shift+z", "cmd+tab"] {
            XCTAssertNil(DestructiveKeyChords.consequence(ofRaw: raw), "「\(raw)」不該被當成危險")
        }
    }

    /// **解析不了 ≠ 無害。** 不知道它會做什麼，那更該問人。
    func testUnparseableChordCountsAsDangerous() {
        XCTAssertNotNil(DestructiveKeyChords.consequence(ofRaw: "cmd+hyper+q"))
        XCTAssertNotNil(DestructiveKeyChords.consequence(ofRaw: ""))
    }

    // MARK: - 接上風險分級

    func testClassifierRaisesDestructiveChordsToHigh() {
        let classifier = RiskClassifier()
        let quit = ProposedAction(kind: .keypress("cmd+q"))
        XCTAssertEqual(classifier.classify(quit), .high)
        XCTAssertNotNil(classifier.reasonForHigh(quit), "high 一定要說得出後果，否則 HUD 沒東西可顯示")

        let save = ProposedAction(kind: .keypress("cmd+s"))
        XCTAssertEqual(classifier.classify(save), .medium)
        XCTAssertNil(classifier.reasonForHigh(save))
    }

    /// 帶換行的輸入等同「打完再按 Enter」，而 Enter 是送出的那一下。
    func testTypeTextWithNewlineIsNotLow() {
        let classifier = RiskClassifier()
        XCTAssertEqual(classifier.classify(ProposedAction(kind: .typeText("hello"))), .low)
        XCTAssertEqual(classifier.classify(ProposedAction(kind: .typeText("hello\n"))), .medium)
        XCTAssertEqual(classifier.classify(ProposedAction(kind: .typeText("a\r\nb"))), .medium)
    }
}
