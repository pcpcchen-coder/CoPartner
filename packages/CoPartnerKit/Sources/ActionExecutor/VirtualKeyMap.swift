import Carbon.HIToolbox
// 設計：backlog step 53.6-B。`KeyChord.key`（正規化後的鍵名）→ 虛擬鍵碼。
//
// ## 為什麼用 Carbon 的具名常數而不是寫死數字
//
// 這張表如果用數字寫（`"q": 12`），錯一個數字的後果不是「按不到」，是**按到別的鍵**
// ——而 12 與 13 在畫面上差的是 `q` 和 `w`，在 `⌘Q` 與 `⌘W` 之間差的是「結束 app」
// 與「關閉視窗」。用 `kVK_ANSI_Q` 則不可能打錯：打錯就編不過。
//
// ## 為什麼認不得就回 nil
//
// 與 `KeyChord.parse` 同一條規則：**HUD 上顯示的必須就是實際按下去的**。
// 猜一個鍵碼、或退回某個「差不多」的鍵，都會讓使用者核准的與實際發生的是兩件事。
// 認不得就整條動作拒絕，不送。
//
// ⚠️ 這張表是 **ANSI（美式）鍵盤佈局**的位置碼。非美式佈局下，同一個位置印的字母可能不同
// ——這是 `CGEvent(keyboardEventSource:virtualKey:keyDown:)` 的本質限制，不是這張表的錯。
// 文字輸入因此走 `keyboardSetUnicodeString`（與佈局無關），這張表只服務**組合鍵**，
// 而組合鍵（⌘C／⌘V／⌘Q）在各佈局上位置一致。
public enum VirtualKeyMap {

    /// 鍵名 → 虛擬鍵碼。認不得回 nil。
    public static func keyCode(for key: String) -> Int? { table[key] }

    /// 這張表涵蓋的所有鍵名（測試與診斷用）。
    public static var knownKeys: [String] { table.keys.sorted() }

    private static let table: [String: Int] = {
        var t: [String: Int] = [
            // 字母（`KeyChord` 已正規化成小寫）
            "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D,
            "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H,
            "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
            "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P,
            "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
            "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
            "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
            // 數字
            "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
            "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7,
            "8": kVK_ANSI_8, "9": kVK_ANSI_9,
            // 標點（`KeyChord` 讓分隔符本身也能當主鍵，所以 - 和 + 一定要在）
            "-": kVK_ANSI_Minus, "+": kVK_ANSI_Equal,      // ⌘+ 實際上是 ⌘⇧= 的位置鍵
            "=": kVK_ANSI_Equal, "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket,
            "\\": kVK_ANSI_Backslash, ";": kVK_ANSI_Semicolon, "'": kVK_ANSI_Quote,
            ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period, "/": kVK_ANSI_Slash,
            "`": kVK_ANSI_Grave,
            // 具名鍵（鍵名與 `KeyChord.namedKeys` 的正規化結果一致）
            "return": kVK_Return, "enter": kVK_ANSI_KeypadEnter,
            "tab": kVK_Tab, "space": kVK_Space, "escape": kVK_Escape,
            "delete": kVK_Delete, "forwarddelete": kVK_ForwardDelete,
            "up": kVK_UpArrow, "down": kVK_DownArrow,
            "left": kVK_LeftArrow, "right": kVK_RightArrow,
            "home": kVK_Home, "end": kVK_End,
            "pageup": kVK_PageUp, "pagedown": kVK_PageDown,
            "capslock": kVK_CapsLock,
        ]
        let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7,
                            kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12, kVK_F13, kVK_F14,
                            kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
        for (index, code) in functionKeys.enumerated() { t["f\(index + 1)"] = code }
        return t
    }()
}
