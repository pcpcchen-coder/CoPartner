import Foundation
import CoreGraphics
import ApplicationServices
// 設計：docs/design/v2_smart-capture-engine.md §B.4
// 🔒 真機膠水：需 Accessibility 權限；實際讀取行為於 step 10 真機驗收，CI 只保證編譯。
// 現提供 on-demand 讀取 focused element；AXObserver 反應式通知留待後續（見 TODO）。

/// 用 AXUIElement 讀取「系統目前焦點元件」的 role / value / frame（§B.4）。
public final class SystemAXFocusProvider: AXFocusProviding {
    private let systemWide = AXUIElementCreateSystemWide()
    public init() {}

    public func focusedElement() -> AXFocusedElement? {
        guard let focused = copyElement(systemWide, kAXFocusedUIElementAttribute as CFString) else { return nil }
        let role = copyString(focused, kAXRoleAttribute as CFString) ?? "AXUnknown"
        let subrole = copyString(focused, kAXSubroleAttribute as CFString)
        let value = copyString(focused, kAXValueAttribute as CFString)
        let frame = copyFrame(focused) ?? .zero
        return AXFocusedElement(role: role, subrole: subrole, frame: frame, value: value)
    }

    // TODO(step 10+): AXObserver 訂閱 focused element / window 變更以反應式觸發（§B.3.1）。

    private func copyElement(_ element: AXUIElement, _ attribute: CFString) -> AXUIElement? {
        var out: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &out) == .success,
              let out, CFGetTypeID(out) == AXUIElementGetTypeID() else { return nil }
        return (out as! AXUIElement)
    }

    private func copyString(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var out: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &out) == .success, let out else { return nil }
        return out as? String
    }

    private func copyFrame(_ element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, let sizeRef,
              CFGetTypeID(posRef) == AXValueGetTypeID(),
              CFGetTypeID(sizeRef) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        _ = AXValueGetValue(posRef as! AXValue, .cgPoint, &point)
        _ = AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }
}
