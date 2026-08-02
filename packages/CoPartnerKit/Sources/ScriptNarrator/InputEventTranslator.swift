import Foundation
// 設計：docs/design/v2.1_action-script-narrator.md §2（TYPE / PASTE / SCROLL 事件）
// 把「已從 CGEvent 抽出的原始輸入資料」翻成 L0 事件。純邏輯、CI 可測；
// CGEvent 抽取本身（捲動位移、打字 unicode、⌘V 偵測）在 InputEventTap（🔒 真機）。

public enum InputEventTranslator {
    /// 捲動位移 → L0 scroll。取絕對值較大的軸決定方向（垂直優先於平手），距離為該軸絕對值。
    /// 符號依 CGEvent 軸向：deltaY>0→up、<0→down；deltaX>0→right、<0→left。無位移回 nil。
    public static func scroll(app: String, deltaX: Int, deltaY: Int) -> L0Event? {
        guard deltaX != 0 || deltaY != 0 else { return nil }
        if abs(deltaY) >= abs(deltaX) {
            return .scroll(app: app, direction: deltaY > 0 ? .up : .down, distance: abs(deltaY))
        }
        return .scroll(app: app, direction: deltaX > 0 ? .right : .left, distance: abs(deltaX))
    }

    /// 一個在欄位裡打的字 → L0 type。**安全欄位一律回占位、永不記錄實際字元**；
    /// 控制 / 功能鍵（backspace/enter/tab/方向鍵…）不成字回 nil。逐字由 EventLog 合併成句（§2）。
    public static func type(field: String, character: String, isSecureField: Bool) -> L0Event? {
        if isSecureField { return .type(field: field, text: PIIMasker.secureFieldPlaceholder) }
        guard isLoggable(character) else { return nil }
        return .type(field: field, text: character)
    }

    /// 貼上內容 → L0 paste（預覽經 PIIMasker 遮罩；原始字元數保留供稽核）。空內容回 nil。
    public static func paste(clipboard: String, maxPreview: Int = 30) -> L0Event? {
        guard !clipboard.isEmpty else { return nil }
        let (chars, preview) = PIIMasker.pastePreview(clipboard, maxPreview: maxPreview)
        return .paste(chars: chars, preview: preview)
    }

    /// 依 AX role / subrole 判定是否為安全（密碼）欄位。
    public static func isSecure(role: String?, subrole: String?) -> Bool {
        role == "AXSecureTextField" || subrole == "AXSecureTextField"
    }

    /// 可入劇本的可見字元：排除控制字元（<0x20、0x7F）與功能鍵私用區（0xF700–0xF8FF）。
    private static func isLoggable(_ s: String) -> Bool {
        guard !s.isEmpty else { return false }
        for scalar in s.unicodeScalars {
            if scalar.value < 0x20 || scalar.value == 0x7F { return false }
            if (0xF700...0xF8FF).contains(scalar.value) { return false }
        }
        return true
    }
}
