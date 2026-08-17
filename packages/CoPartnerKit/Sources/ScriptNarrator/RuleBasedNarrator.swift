import Foundation
import CoPartnerCore
// 設計：§5 fallback 階梯底層——純規則模板，零模型成本，**非空輸入永不回 nil**（降級但不中斷）。
// 從 L0 事件日誌行（EventFormatter 格式：`[時間] KEYWORD app=… …`）以關鍵字/regex 推導欄位。

public struct RuleBasedNarrator: NarrationBackend {
    /// 固定時鐘（測試注入）。nil = 每次敘事都取當下時間。
    ///
    /// ⚠️ 不可改回 `init(now: Date = Date())`：那會在**建構時**就把時間釘死。
    /// app 端的階梯是長期存活的一份（建一次用整個觀察期），結果會是所有規則式 step
    /// 共用啟動當下的時間戳，熱環的時間窗過濾與記憶層排序全毀。
    private let fixedNow: Date?
    public init(now: Date? = nil) { self.fixedNow = now }

    public func narrate(_ lines: [String]) async -> ActionStep? {
        let cleaned = lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !cleaned.isEmpty else { return nil }
        let joined = cleaned.joined(separator: "\n")
        return ActionStep(
            startedAt: fixedNow ?? Date(),
            app: Self.inferApp(cleaned) ?? "未知",
            category: Self.inferCategory(joined),
            whatHappened: Self.describe(cleaned),
            inferredGoal: "（規則式推測，未使用模型）",
            confidence: 0.3,
            artifacts: Self.extractArtifacts(from: joined),
            openLoop: Self.looksOpenLoop(cleaned.last ?? "")
        )
    }

    // MARK: - 純規則 helpers（皆確定性、CI 可測）

    private static let separators: Set<Character> = [
        " ", "\n", "\t", ",", "，", "。", "、", ";", "；", "\"", "「", "」",
        "（", "）", "(", ")", "=", "[", "]", "<", ">",
    ]
    private static let fileExtensions: Set<String> = [
        "swift", "py", "js", "ts", "tsx", "md", "txt", "json", "yaml", "yml", "log",
        "png", "jpg", "jpeg", "pdf", "html", "css", "rs", "go", "java", "c", "cpp", "h", "m",
    ]

    /// 這段視窗裡**佔比最高**的 app；平手時取較晚出現的那個。
    ///
    /// ⚠️ 原本取的是「第一行的 app」，step 54 dogfood 證明那是錯的：
    /// 視窗是舊到新排的，第一行是這段時間的**最舊**事件，於是每個 step 都被標成
    /// 「這段開始時你在哪」而不是「這段主要在哪」——真機上整串 step 都掛著 `CoPartner`，
    /// 內容講的卻是 AnyDesk 和系統設定。
    ///
    /// 這不只是顯示難看：`MemoryStore` 依 app 存放 step，標錯等於之後全部查錯戶。
    ///
    /// 平手取較晚者，是因為一個 step 通常結束在使用者**當下**所在的 app，
    /// 那也是接手時最可能相關的那個。
    ///
    /// public 而非 internal：測試在別的 module 看不到 internal 成員
    /// （`SSEFrameParser.splitField`、`TakeoverHUDPresentation.label` 都踩過這坑）。
    public static func inferApp(_ lines: [String]) -> String? {
        var counts: [String: Int] = [:]
        var lastSeen: [String: Int] = [:]
        for (index, line) in lines.enumerated() {
            guard let name = appName(in: line) else { continue }
            counts[name, default: 0] += 1
            lastSeen[name] = index
        }
        return counts.max {
            ($0.value, lastSeen[$0.key] ?? 0) < ($1.value, lastSeen[$1.key] ?? 0)
        }?.key
    }

    /// 從一行日誌取 app 名。
    ///
    /// 不能單純「切到第一個空白」——app 名稱本身可以有空白（"Google Chrome"、
    /// "Visual Studio Code"），那樣會把 Chrome 切成 "Google"。改成切在**下一個看起來像
    /// 欄位鍵的 token**（`win=` / `dir=` / `dist=`）之前，那才是 EventFormatter 的真實格式。
    public static func appName(in line: String) -> String? {
        guard let r = line.range(of: "app=") else { return nil }
        let rest = line[r.upperBound...]
        var end = rest.endIndex
        var cursor = rest.startIndex
        while let space = rest[cursor...].firstIndex(of: " ") {
            let afterSpace = rest.index(after: space)
            if looksLikeFieldKey(rest[afterSpace...]) { end = space; break }
            guard afterSpace < rest.endIndex else { break }
            cursor = afterSpace
        }
        let name = rest[..<end].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    /// `win="…"` 這種欄位開頭：第一個 `=` 之前全是小寫英文字母。
    private static func looksLikeFieldKey(_ s: Substring) -> Bool {
        guard let eq = s.firstIndex(of: "=") else { return false }
        let key = s[..<eq]
        return !key.isEmpty && key.allSatisfy { $0.isLetter && $0.isLowercase }
    }

    /// 依關鍵字優先序推類別（debugging 最優先，operating 保底）。
    static func inferCategory(_ text: String) -> String {
        let lower = text.lowercased()
        func has(_ ks: [String]) -> Bool { ks.contains { lower.contains($0.lowercased()) } }
        if has(["error", "錯誤", "exception", "crash", "失敗", "1006", "bug", "debug"]) { return "debugging" }
        if has(["搜尋", "search", "google", "查詢", "查文件"]) { return "searching" }
        if has(["type", "paste", "輸入", "貼上", "撰寫", "編輯"]) { return "editing" }
        if has(["scroll", "捲動", "閱讀", "瀏覽"]) { return "reading" }
        if has(["watch", "影片", "播放"]) { return "watching" }
        return "operating"
    }

    /// 末行為 TYPE/PASTE（進行中輸入）→ 視為 open loop。
    static func looksOpenLoop(_ lastLine: String) -> Bool {
        let u = lastLine.uppercased()
        return u.contains("TYPE") || u.contains("PASTE")
    }

    /// 抽 artifacts：URL（http/https）與已知副檔名的檔名。去重、上限 8。
    static func extractArtifacts(from text: String) -> [String] {
        var found: [String] = []
        for token in text.split(whereSeparator: { separators.contains($0) }) {
            let s = String(token)
            if s.hasPrefix("http://") || s.hasPrefix("https://") {
                if !found.contains(s) { found.append(s) }
            } else if let dot = s.lastIndex(of: "."), dot != s.startIndex,
                      s.index(after: dot) < s.endIndex {
                let ext = s[s.index(after: dot)...].lowercased()
                if fileExtensions.contains(ext), !found.contains(s) { found.append(s) }
            }
        }
        return Array(found.prefix(8))
    }

    /// 客觀敘述：單行直述，多行給筆數與首尾。
    static func describe(_ lines: [String]) -> String {
        if lines.count == 1 { return humanize(lines[0]) }
        return "\(lines.count) 個操作（\(humanize(lines.first!)) … \(humanize(lines.last!))）"
    }

    /// 去掉行首 `[時間]` 前綴，留可讀內容。
    static func humanize(_ line: String) -> String {
        if let close = line.firstIndex(of: "]") {
            return String(line[line.index(after: close)...]).trimmingCharacters(in: .whitespaces)
        }
        return line.trimmingCharacters(in: .whitespaces)
    }
}
