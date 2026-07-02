import Foundation
import CoreGraphics
// 設計：docs/design/v2_smart-capture-engine.md §B.3
// 🔒 真機膠水：實際攔截行為需 Input Monitoring 權限 + run loop，於 step 10 真機驗收；
//    CI 只保證「編譯得過」。映射邏輯本身在 EventTapMapper（已由 CI 測試覆蓋）。

/// 全域輸入事件 tap：監聽 mouseDown / mouseMoved / dragged / scroll / keyDown，
/// 用 `EventTapMapper` 映射成 `AttentionModel.Signal` 後交給 `handler`。
/// `.listenOnly`（不改事件流），並處理 OS 逾時 / 使用者輸入導致的停用（重新啟用）。
public final class InputEventTap {
    public typealias Handler = @Sendable (AttentionModel.Signal) -> Void

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
        let delta = CGVector(dx: Double(event.getIntegerValueField(.mouseEventDeltaX)),
                             dy: Double(event.getIntegerValueField(.mouseEventDeltaY)))
        if let signal = EventTapMapper.signal(for: type, mouseDelta: delta) {
            handler(signal)
        }
    }
}
