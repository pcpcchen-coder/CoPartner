import XCTest
import Carbon.HIToolbox
@testable import ActionExecutor

/// 鍵名 → 虛擬鍵碼（step 53.6-B）。
///
/// 這張表錯一個項目的後果不是「按不到」，是**按到別的鍵**——而 `⌘Q`（結束 app）
/// 與 `⌘W`（關閉視窗）之間就差一個碼。所以最重要的一條測試不是「某個鍵對不對」，
/// 是**解析得出來的鍵，執行端一定要按得下去**。
final class VirtualKeyMapTests: XCTestCase {

    /// 🔑 **跨模組不變式。** `KeyChord` 解析得出來的每一個具名鍵，
    /// `VirtualKeyMap` 都必須映射得到。少了這條，一個組合鍵可以解析成功卻在真機上
    /// 映射不到鍵碼——而那要等到使用者在 HUD 按下「執行」的那一刻才會發現。
    func testEveryParseableNamedKeyIsMappable() {
        for name in KeyChord.knownKeyNames {
            XCTAssertNotNil(VirtualKeyMap.keyCode(for: name),
                            "「\(name)」解析得出來，卻按不下去")
        }
    }

    /// 字母、數字、以及 `KeyChord` 允許當主鍵的分隔符也要全部映射得到。
    func testAsciiKeysAndSeparatorKeysAreMappable() throws {
        for scalar in "abcdefghijklmnopqrstuvwxyz0123456789" {
            XCTAssertNotNil(VirtualKeyMap.keyCode(for: String(scalar)), String(scalar))
        }
        for key in ["-", "+"] {                       // "cmd+-" / "cmd++" 解析得出來
            let chord = try KeyChord.parse("cmd+\(key)")
            XCTAssertNotNil(VirtualKeyMap.keyCode(for: chord.key), key)
        }
    }

    /// 幾個**後果最嚴重**的鍵直接對照 Carbon 常數釘死。
    func testDestructiveKeysMapToTheRightCodes() {
        XCTAssertEqual(VirtualKeyMap.keyCode(for: "q"), kVK_ANSI_Q)
        XCTAssertEqual(VirtualKeyMap.keyCode(for: "w"), kVK_ANSI_W)
        XCTAssertEqual(VirtualKeyMap.keyCode(for: "delete"), kVK_Delete)
        XCTAssertEqual(VirtualKeyMap.keyCode(for: "escape"), kVK_Escape)
        XCTAssertNotEqual(VirtualKeyMap.keyCode(for: "q"), VirtualKeyMap.keyCode(for: "w"),
                          "⌘Q 是結束 app、⌘W 是關閉視窗——這兩個混起來後果差很多")
    }

    /// 每個鍵碼只對應一個意義上的鍵；重複的碼代表表打錯了。
    /// （`+` 與 `=` 是同一個實體鍵，是唯一容許的重複。）
    func testNoAccidentalDuplicateCodes() {
        var seen: [Int: [String]] = [:]
        for name in VirtualKeyMap.knownKeys {
            guard let code = VirtualKeyMap.keyCode(for: name) else { continue }
            seen[code, default: []].append(name)
        }
        for (code, names) in seen where names.count > 1 {
            XCTAssertEqual(Set(names), ["+", "="],
                           "鍵碼 \(code) 對到多個鍵：\(names.sorted())")
        }
    }

    /// **認不得就回 nil，不猜。** 猜一個「差不多」的鍵，會讓使用者核准的與實際按下的
    /// 是兩件事——與 `KeyChord.parse` 同一條規則。
    func testUnknownKeyReturnsNil() {
        for key in ["hyper", "眼睛", "", "f21", "F1"] {   // "F1" 大寫：正規化是呼叫端的責任
            XCTAssertNil(VirtualKeyMap.keyCode(for: key), key)
        }
    }

    func testFunctionKeysCoverF1ThroughF20() {
        for i in 1...20 {
            XCTAssertNotNil(VirtualKeyMap.keyCode(for: "f\(i)"), "f\(i)")
        }
    }
}
