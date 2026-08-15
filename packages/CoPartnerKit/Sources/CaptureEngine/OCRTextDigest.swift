import Foundation
// 把 OCR segments 收斂成一段可讀摘要（給選單顯示 / 餵 L1 narrator context）。純邏輯、CI 可測。
// 依信心過濾、依 bbox 由上到下排序後串接、截長。

public enum OCRTextDigest {
    /// bbox 的 y 軸慣例。**Vision 回左下原點**（y 越大越上面）；某些來源用左上原點（y 越小越上面）。
    /// 搞錯會讓摘要上下顛倒——所以要求呼叫端明講，不用猜的。
    public enum BBoxOrigin: Sendable {
        case bottomLeft   // Vision（VNRecognizeTextRequest.boundingBox）
        case topLeft      // 螢幕座標慣例
    }

    public static func snippet(from segments: [OCRSegment],
                              minConfidence: Double = 0.5,
                              maxChars: Int = 120,
                              origin: BBoxOrigin = .topLeft) -> String {
        let kept = segments
            .filter { $0.confidence >= minConfidence }
            .sorted { readingOrder($0, origin) < readingOrder($1, origin) }
            .map { $0.text }
        let joined = kept.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard joined.count > maxChars else { return joined }
        return String(joined.prefix(maxChars)) + "…"
    }

    /// 閱讀順序鍵（越小越先）：左上原點直接用 y；左下原點取負值（y 大者在上、應先讀）。
    /// bbox 慣例 [x, y, w, h]；缺 y 就當 0。
    private static func readingOrder(_ s: OCRSegment, _ origin: BBoxOrigin) -> Double {
        let y = s.bbox.count > 1 ? s.bbox[1] : 0
        switch origin {
        case .topLeft: return y
        case .bottomLeft: return -y
        }
    }
}
