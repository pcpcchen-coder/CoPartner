import Foundation
// 設計：docs/design/v2.1_action-script-narrator.md §2（L0 事件日誌，deterministic 模板、零模型成本）
// 純字串格式化，無平台依賴，全部由 CI 驗證。

/// L0 顯著事件（只有「成行」的事件成為一個 case；滑鼠移動不記，只更新 attention）。
public enum L0Event: Sendable, Equatable {
    case focus(app: String, window: String)            // 焦點視窗
    case type(field: String, text: String)             // 文字輸入（同欄位 2s 內合併，見 step 6）
    case paste(chars: Int, preview: String)            // 貼上（preview 截斷 + PII 遮罩，見 step 7）
    case switchApp(app: String, window: String)        // 切換到不同 app
    case scroll(app: String, direction: ScrollDirection, distance: Int) // 捲動（1s 視窗聚合，見 step 6）
    case watch(kind: String)                           // DYNAMIC tile（如 video），只記一次

    public enum ScrollDirection: String, Sendable, Equatable { case up, down, left, right }
}

/// 把 L0 事件格式化成一行 human-readable 日誌（§2 範例格式，欄位對齊）。
public enum EventFormatter {
    private static let keywordWidth = 8   // 關鍵字左對齊補到此寬度，使欄位起點對齊

    /// 產生一行日誌。`timeZone` 可注入以利決定性測試（預設本地時間）。
    public static func line(_ event: L0Event, at timestamp: Date, timeZone: TimeZone = .current) -> String {
        let (keyword, fields) = keywordAndFields(event)
        let padded = keyword.padding(toLength: keywordWidth, withPad: " ", startingAt: 0)
        return "[\(clockString(timestamp, timeZone: timeZone))] \(padded)\(fields)"
    }

    private static func keywordAndFields(_ event: L0Event) -> (String, String) {
        switch event {
        case let .focus(app, window):     return ("FOCUS",  "app=\(app) win=\"\(window)\"")
        case let .type(field, text):      return ("TYPE",   "field=\(field) text=\"\(text)\"")
        case let .paste(chars, preview):  return ("PASTE",  "chars=\(chars) preview=\"\(preview)\"")
        case let .switchApp(app, window): return ("SWITCH", "app=\(app) win=\"\(window)\"")
        case let .scroll(app, dir, dist): return ("SCROLL", "app=\(app) dir=\(dir.rawValue) dist=\(dist)")
        case let .watch(kind):            return ("WATCH",  kind)
        }
    }

    /// `HH:mm:ss.SSS`（毫秒補零到三位）。用 en_US_POSIX 固定，不受地區設定影響。
    private static func clockString(_ date: Date, timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: date)
    }
}
