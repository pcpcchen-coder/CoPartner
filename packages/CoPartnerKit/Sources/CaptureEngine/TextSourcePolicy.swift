import Foundation
import CoPartnerCore
// 設計：§B.4 / §B.8（AX 文字優先——能從 Accessibility 直接取文字的 tile 不必跑 OCR）。
// 純決策、CI 可測；組合 step 22 的 CaptureThrottle。

/// 某 tile 這次的文字來源。
public enum TextSource: Sendable, Equatable {
    case accessibility   // 直接用 AX 文字（免 OCR，最省最準）
    case ocr             // 跑 OCR
    case skip            // 這次不取文字（cold / dynamic / 節流中）
}

public enum TextSourcePolicy {
    /// 決定文字來源：有 AX 文字 → 一律用 AX（不管狀態）；否則交給節流依 tile 狀態決定 OCR or skip。
    public static func source(hasAXText: Bool,
                              state: TileEvent.State,
                              throttle: CaptureThrottle,
                              sinceLastOCR: TimeInterval) -> TextSource {
        if hasAXText { return .accessibility }
        return throttle.shouldOCR(state: state, sinceLastOCR: sinceLastOCR) ? .ocr : .skip
    }
}
