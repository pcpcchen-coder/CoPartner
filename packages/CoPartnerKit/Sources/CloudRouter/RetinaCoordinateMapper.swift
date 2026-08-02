import Foundation
// 設計：§E「Retina 座標 ÷2」。Claude 在原生像素截圖上回像素座標；CGEvent 用邏輯點，需 ÷scale。
// 純幾何、CI 可測。四捨五入固定（.toNearestOrAwayFromZero），保證整數邏輯點 →pixels→logical round-trip。

public enum RetinaCoordinateMapper {
    /// 邏輯點 → 實體像素（×scale）。
    public static func toPixels(_ point: (x: Int, y: Int), scale: Int = 2) -> (x: Int, y: Int) {
        let s = max(1, scale)
        return (point.x * s, point.y * s)
    }

    /// 模型回的像素座標 → 邏輯點（÷scale，固定四捨五入）。
    public static func toLogical(_ pixel: (x: Int, y: Int), scale: Int = 2) -> (x: Int, y: Int) {
        let s = max(1, scale)
        return (divRound(pixel.x, s), divRound(pixel.y, s))
    }

    private static func divRound(_ v: Int, _ s: Int) -> Int {
        Int((Double(v) / Double(s)).rounded())
    }
}
