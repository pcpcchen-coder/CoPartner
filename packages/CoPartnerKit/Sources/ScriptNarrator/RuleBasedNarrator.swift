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

    /// 從含 `app=…` 的行取第一個 app 名（到下一個空白為止）。
    static func inferApp(_ lines: [String]) -> String? {
        for line in lines {
            guard let r = line.range(of: "app=") else { continue }
            let name = line[r.upperBound...].prefix { $0 != " " }
            if !name.isEmpty { return String(name) }
        }
        return nil
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
