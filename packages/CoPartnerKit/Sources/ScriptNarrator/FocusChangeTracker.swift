import Foundation
// 設計：§B.4（焦點追蹤）。把「焦點觀測序列」轉成 FOCUS / SWITCH 事件。純值邏輯、可測。

/// 追蹤 app / 視窗焦點變化：換 app → SWITCH，同 app 換視窗 → FOCUS，無變化 → nil。
/// 這是「操作時間機器」骨架最乾淨的訊號來源（不需重建打字內容）。
public struct FocusChangeTracker: Sendable {
    private var lastApp: String?
    private var lastWindow: String?
    public init() {}

    /// 餵入一次焦點觀測，回傳應記錄的事件；無變化回 nil。
    public mutating func event(app: String, window: String) -> L0Event? {
        defer { lastApp = app; lastWindow = window }
        if app != lastApp { return .switchApp(app: app, window: window) }
        if window != lastWindow { return .focus(app: app, window: window) }
        return nil
    }
}
