import Foundation
// 設計：sandbox-threat-model.md I2/T9 ＋ backlog step 53.6。
//
// 把 `"cmd+shift+q"` 這種字串解析成一個**明確的**組合鍵。
//
// ## 為什麼不能「認得幾個算幾個」
//
// 最自然的寫法是掃描字串、認得的修飾鍵就加上去、不認得的就跳過。那會造成
// **HUD 上顯示的與實際按下的不是同一件事**：使用者看到 `cmd+shift+q` 按了確認，
// 解析器悄悄丟掉不認得的部分，實際送出 `cmd+q`——他核准的是登出，發生的是結束 app，
// 或者反過來。人工確認閘門的整個價值建立在「確認的內容 == 執行的內容」上。
//
// 所以：**認不得就整個丟出錯誤**，不猜、不補、不忽略。
//
// ## 為什麼要正規化
//
// `"Cmd+Q"`、`"⌘Q"`、`"command+q"` 是同一個組合鍵。不正規化的話，危險組合鍵的
// 比對表就得列出所有寫法，而漏掉任何一種寫法＝那個危險組合鍵靜默降級成 medium。
public struct KeyChord: Sendable, Equatable, Hashable {

    public enum Modifier: String, Sendable, Equatable, Hashable, CaseIterable, Comparable {
        case control, option, shift, command, function

        /// 顯示順序固定為 ⌃⌥⇧⌘（macOS 慣例），讓同一個組合鍵永遠印成同一個字串。
        public static func < (a: Modifier, b: Modifier) -> Bool {
            order(a) < order(b)
        }
        private static func order(_ m: Modifier) -> Int {
            switch m {
            case .control: return 0
            case .option: return 1
            case .shift: return 2
            case .command: return 3
            case .function: return 4
            }
        }
        public var symbol: String {
            switch self {
            case .control: return "⌃"
            case .option: return "⌥"
            case .shift: return "⇧"
            case .command: return "⌘"
            case .function: return "fn"
            }
        }
    }

    public let modifiers: Set<Modifier>
    /// 正規化後的主鍵：單一小寫字元（`"q"`），或固定表裡的名稱（`"delete"`）。
    public let key: String

    public init(modifiers: Set<Modifier>, key: String) {
        self.modifiers = modifiers
        self.key = key
    }

    public enum ParseError: Error, Equatable {
        case empty
        /// 認不得的片段。**帶著原文**——「解析失敗」而不說是哪裡失敗，
        /// 下次遇到只能再猜一次。
        case unknownToken(String)
        /// 有修飾鍵但沒有主鍵（`"cmd+"`），或有兩個主鍵（`"cmd+q+w"`）。
        case malformed(String)
    }

    private static let modifierAliases: [String: Modifier] = [
        "cmd": .command, "command": .command, "⌘": .command, "meta": .command, "super": .command,
        "opt": .option, "option": .option, "alt": .option, "⌥": .option,
        "ctrl": .control, "control": .control, "⌃": .control,
        "shift": .shift, "⇧": .shift,
        "fn": .function, "function": .function,
    ]

    /// 具名主鍵。**白名單而不是黑名單**：不在表上的名稱寧可解析失敗，
    /// 也不要當成「一個叫做 `retunr` 的字元鍵」送出去。
    private static let namedKeys: [String: String] = {
        var table: [String: String] = [
            "return": "return", "enter": "enter", "tab": "tab", "space": "space",
            "escape": "escape", "esc": "escape",
            "delete": "delete", "backspace": "delete",
            "forwarddelete": "forwarddelete",
            "up": "up", "down": "down", "left": "left", "right": "right",
            "home": "home", "end": "end", "pageup": "pageup", "pagedown": "pagedown",
            "capslock": "capslock",
        ]
        for i in 1...20 { table["f\(i)"] = "f\(i)" }
        return table
    }()

    /// 解析組合鍵字串。接受 `+` 或 `-` 分隔，以及緊貼的符號寫法（`"⌘⇧Q"`）。
    public static func parse(_ raw: String) throws -> KeyChord {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ParseError.empty }

        var modifiers: Set<Modifier> = []
        var mainKey: String?

        for token in tokenize(trimmed) {
            var piece = token.trimmingCharacters(in: .whitespaces)
            // 先剝掉緊貼在前面的符號修飾鍵（"⌘⇧Q" 是一個 token，不是三個）。
            while let first = piece.first, let modifier = modifierAliases[String(first)] {
                modifiers.insert(modifier)
                piece.removeFirst()
            }
            if piece.isEmpty { continue }              // 整個 token 都是符號修飾鍵
            let lowered = piece.lowercased()
            if let modifier = modifierAliases[lowered] {
                modifiers.insert(modifier)
                continue
            }
            let resolved: String
            if let named = namedKeys[lowered] {
                resolved = named
            } else if lowered.count == 1 {
                resolved = lowered
            } else {
                throw ParseError.unknownToken(piece)
            }
            // 兩個主鍵代表這根本不是一個組合鍵——按順序敲兩下和同時按不是同一回事。
            guard mainKey == nil else { throw ParseError.malformed(trimmed) }
            mainKey = resolved
        }
        guard let key = mainKey else { throw ParseError.malformed(trimmed) }
        return KeyChord(modifiers: modifiers, key: key)
    }

    /// 按 `+` / `-` 切開，但**分隔符本身也可能是主鍵**（`"cmd+-"` 是縮小、`"cmd++"` 是放大）。
    /// 規則：分隔符出現在一個空片段的位置時，它就是內容而不是分隔符。
    /// 直接用 `split` 會把 `"cmd+-"` 解析成「只有修飾鍵、沒有主鍵」。
    private static func tokenize(_ s: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for ch in s {
            if ch == "+" || ch == "-" {
                if current.isEmpty {
                    current.append(ch)          // 空位置上的分隔符 → 它是內容
                } else {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    /// 正規寫法，給 HUD 與比對表共用。**HUD 顯示的必須是這個**——
    /// 顯示原文、比對正規化後的值，等於讓兩者有機會不一致。
    public var canonical: String {
        modifiers.sorted().map(\.symbol).joined() + key.uppercased()
    }
}

/// 已知會造成**難以復原**後果的組合鍵。
///
/// 這張表刻意只列「按下去就回不來」的：關掉沒存的東西、刪東西、強制結束、登出。
/// 一般的 ⌘S、⌘C、⌘Z 不在這裡——把所有組合鍵都列成 high 等於沒有分級。
///
/// 表只增不減，每一筆都要說得出後果。
public enum DestructiveKeyChords {

    private static let table: [KeyChord: String] = [
        KeyChord(modifiers: [.command], key: "q"): "結束 app（未存的變更可能直接消失）",
        KeyChord(modifiers: [.command], key: "w"): "關閉視窗／分頁（未存的變更可能直接消失）",
        KeyChord(modifiers: [.command], key: "delete"): "把選取項目丟進垃圾桶",
        KeyChord(modifiers: [.command, .shift], key: "delete"): "清空垃圾桶（**不可復原**）",
        KeyChord(modifiers: [.command, .option], key: "escape"): "開啟「強制結束應用程式」",
        KeyChord(modifiers: [.command, .option, .shift], key: "escape"): "強制結束最前方的 app（不會問你要不要存檔）",
        KeyChord(modifiers: [.command, .shift], key: "q"): "登出目前使用者",
        KeyChord(modifiers: [.command, .control], key: "q"): "鎖定螢幕",
        KeyChord(modifiers: [.command, .option], key: "w"): "關閉該 app 的**所有**視窗",
    ]

    /// 這個組合鍵的後果說明；不在表上回 nil。
    public static func consequence(of chord: KeyChord) -> String? { table[chord] }

    /// 便利入口：直接吃原始字串。
    ///
    /// **解析不了時回傳的是「說不出它會做什麼」而不是 nil**——
    /// 認不得的組合鍵不代表它無害，只代表我們不知道，那更該問人。
    public static func consequence(ofRaw raw: String) -> String? {
        guard let chord = try? KeyChord.parse(raw) else {
            return "無法解析的組合鍵「\(raw)」——說不出它會做什麼，因此當成危險處理"
        }
        return consequence(of: chord)
    }
}
