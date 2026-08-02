import Foundation
import CoreGraphics
// 設計：docs/design/v2_smart-capture-engine.md §B.3
// 🔒 真機膠水：實際攔截行為需 Input Monitoring 權限 + run loop，於 step 10 真機驗收；
//    CI 只保證「編譯得過」。映射邏輯本身在 EventTapMapper（已由 CI 測試覆蓋）。

/// 從一次輸入事件抽出的原始觀測（供注意力/焦點與 L0 劇本共用）。
public enum CapturedInput: Sendable {
    case scroll(deltaX: Int, deltaY: Int)     // 捲動位移
    case keyDown(characters: String)          // 打字的 unicode 字元
    case pasteShortcut                        // ⌘V（呼叫端讀剪貼簿）
    case pointer(AttentionModel.Signal)       // click/drag/move（給注意力/焦點）
}

/// 全域輸入事件 tap：監聽 mouseDown / mouseMoved / dragged / scroll / keyDown，
/// 抽出 `CapturedInput`（捲動位移 / 打字字元 / ⌘V / 指標訊號）交給 `handler`。
/// `.listenOnly`（不改事件流），並處理 OS 逾時 / 使用者輸入導致的停用（重新啟用）。
public final class InputEventTap {
    public typealias Handler = @Sendable (CapturedInput) -> Void

    private let handler: Handler
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    public init(handler: @escaping Handler) { self.handler = handler }

    /// 監聽的事件遮罩。
    private static let mask: CGEventMask =
          ((1 as CGEventMask) << CGEventType.leftMouseDown.rawValue)
        | ((1 as CGEventMask) << CGEventType.rightMouseDown.rawValue)
        | ((1 as CGEventMask) << CGEventType.mouseMoved.rawValue)
        | ((1 as CGEventMask) << CGEventType.leftMouseDragged.rawValue)
        | ((1 as CGEventMask) << CGEventType.rightMouseDragged.rawValue)
        | ((1 as CGEventMask) << CGEventType.scrollWheel.rawValue)
        | ((1 as CGEventMask) << CGEventType.keyDown.rawValue)

    /// 建立並啟用 tap，掛到當前 run loop。回傳 false 代表建立失敗（通常是缺 Input Monitoring 權限）。
    @discardableResult
    public func start() -> Bool {
        // @convention(c) callback 無法捕捉狀態 → 透過 userInfo(refcon) 傳遞 self。
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let this = Unmanaged<InputEventTap>.fromOpaque(refcon).takeUnretainedValue()
            this.dispatch(type: type, event: event)
            return Unmanaged.passUnretained(event)   // .listenOnly：原樣放行
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: Self.mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    /// 停用並自 run loop 卸除。
    public func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        tap = nil
        runLoopSource = nil
    }

    private func dispatch(type: CGEventType, event: CGEvent) {
        // OS 可能因逾時 / 使用者輸入停用 tap，需重新啟用（§B.3）。
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        let captured: CapturedInput?
        switch type {
        case .scrollWheel:
            captured = .scroll(deltaX: Int(event.getIntegerValueField(.scrollWheelEventDeltaAxis2)),
                               deltaY: Int(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)))
        case .keyDown:
            if event.flags.contains(.maskCommand) {
                // ⌘V → 貼上；其他 ⌘ 快捷鍵不算打字。
                captured = event.getIntegerValueField(.keyboardEventKeycode) == 9 ? CapturedInput.pasteShortcut : nil
            } else {
                let chars = Self.unicodeString(from: event)
                captured = chars.isEmpty ? nil : CapturedInput.keyDown(characters: chars)
            }
        default:
            let delta = CGVector(dx: Double(event.getIntegerValueField(.mouseEventDeltaX)),
                                 dy: Double(event.getIntegerValueField(.mouseEventDeltaY)))
            captured = EventTapMapper.signal(for: type, mouseDelta: delta).map(CapturedInput.pointer)
        }
        if let captured { handler(captured) }
    }

    /// 從 keyDown 事件取當前鍵盤配置下的 unicode 字元（可能空，如純修飾鍵）。
    private static func unicodeString(from event: CGEvent) -> String {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: buffer.count,
                                       actualStringLength: &length, unicodeString: &buffer)
        guard length > 0 else { return "" }
        return String(utf16CodeUnits: buffer, count: length)
    }
}
