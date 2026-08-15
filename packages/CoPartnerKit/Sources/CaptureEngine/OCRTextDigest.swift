import Foundation
// 把 OCR segments 收斂成一段可讀摘要（給選單顯示 / 餵 L1 narrator context）。純邏輯、CI 可測。
// 依信心過濾、依 bbox 由上到下排序後串接、截長。

public enum OCRTextDigest {
    public static func snippet(from segments: [OCRSegment],
                               minConfidence: Double = 0.5,
                               maxChars: Int = 120) -> String {
        let kept = segments
            .filter { $0.confidence >= minConfidence }
            .sorted { topOf($0) < topOf($1) }          // bbox y（左上原點）由上到下
            .map { $0.text }
        let joined = kept.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard joined.count > maxChars else { return joined }
        return String(joined.prefix(maxChars)) + "…"
    }

    /// bbox 慣例 [x, y, w, h]；缺 y 就當 0（不排序）。
    private static func topOf(_ s: OCRSegment) -> Double { s.bbox.count > 1 ? s.bbox[1] : 0 }
}
