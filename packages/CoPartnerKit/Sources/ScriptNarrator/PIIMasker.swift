import Foundation
// 設計：docs/privacy/data-classification.md（自訂 PII recognizer）+ v2.1 §2/§6（貼上遮罩、密碼欄占位）
// 隱私關鍵路徑：事件進入 L0 之前先遮罩，漏遮＝PII 進劇本。純邏輯、CI 可測。

public enum PIIMasker {
    public enum Category: String, Sendable { case creditCard, taiwanID, taiwanPhone, chinaID }

    /// 密碼 / 安全欄位輸入的固定占位（永不記錄明文）。
    public static let secureFieldPlaceholder = "[在密碼欄輸入]"

    // data-classification.md 的自訂 recognizer + 常見卡號。
    // TW 樣式刻意不加 \b（可能緊鄰中文，加 \b 反而漏抓）——偏向 fail-safe（寧可多遮）。
    private static let rawPatterns: [(Category, String)] = [
        (.creditCard,  #"\b\d{13,19}\b"#),
        (.creditCard,  #"\b\d{4}[ -]\d{4}[ -]\d{4}[ -]\d{4}\b"#),
        (.taiwanID,    #"[A-Z][12]\d{8}"#),
        (.taiwanPhone, #"09\d{8}"#),
        (.chinaID,     #"\b\d{17}[\dXx]\b"#),
    ]

    // NSRegularExpression 不可變且執行緒安全（Sendable），編譯期共享一份即可。
    private static let compiled: [(Category, NSRegularExpression)] =
        rawPatterns.map { ($0.0, try! NSRegularExpression(pattern: $0.1)) }

    /// 偵測文字中出現的 PII 類別（可能多個）。
    public static func detect(_ text: String) -> Set<Category> {
        let range = NSRange(text.startIndex..., in: text)
        var found: Set<Category> = []
        for (category, re) in compiled where re.firstMatch(in: text, options: [], range: range) != nil {
            found.insert(category)
        }
        return found
    }

    /// 是否含任何 PII。
    public static func containsPII(_ text: String) -> Bool { !detect(text).isEmpty }

    /// 部分遮罩：把每個 PII 比對替換成 token，保留非 PII 脈絡（供「遮罩後可上雲」）。
    public static func redact(_ text: String, token: String = "【已遮罩】") -> String {
        let template = NSRegularExpression.escapedTemplate(for: token)
        var result = text
        for (_, re) in compiled {
            let range = NSRange(result.startIndex..., in: result)
            result = re.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: template)
        }
        return result
    }

    /// 貼上 / 剪下的安全預覽：含 PII → 類別化全遮罩訊息；否則截斷預覽。
    /// 回傳（原始字元數, 安全預覽）；chars 保留原始長度以利稽核「貼了多少」。
    public static func pastePreview(_ content: String, maxPreview: Int = 30) -> (chars: Int, preview: String) {
        let chars = content.count
        if let category = priorityCategory(in: detect(content)) {
            return (chars, category.pasteMaskMessage)
        }
        let preview = content.count > maxPreview ? String(content.prefix(maxPreview)) + "…" : content
        return (chars, preview)
    }

    private static func priorityCategory(in cats: Set<Category>) -> Category? {
        for c in [Category.creditCard, .taiwanID, .chinaID, .taiwanPhone] where cats.contains(c) { return c }
        return nil
    }
}

private extension PIIMasker.Category {
    /// 貼上時的類別化遮罩訊息（對應 v2.1 §6 的 `[貼上疑似卡號，已遮罩]`）。
    var pasteMaskMessage: String {
        switch self {
        case .creditCard:         return "[貼上疑似卡號，已遮罩]"
        case .taiwanID, .chinaID: return "[貼上疑似身分證號，已遮罩]"
        case .taiwanPhone:        return "[貼上疑似電話號碼，已遮罩]"
        }
    }
}
