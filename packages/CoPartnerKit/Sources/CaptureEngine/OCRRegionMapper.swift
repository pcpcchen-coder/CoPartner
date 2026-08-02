import CoreGraphics
// 設計：§B.8（局部 OCR：Vision regionOfInterest 對應 dirty tile）。純幾何、CI 可測。
// Vision 的 regionOfInterest 是正規化 [0,1]、**左下原點**（與螢幕左上原點 y 相反）——這裡負責換算。
// 真 VNRecognizeTextRequest 執行在 sidecar /ocr（ocrmac，step 27）或 Swift Vision（🔒）。

public enum OCRRegionMapper {
    /// 螢幕座標 rect（左上原點）→ Vision regionOfInterest（正規化、左下原點），夾到 [0,1]。
    public static func normalizedROI(screenRect: CGRect, screenWidth: Int, screenHeight: Int) -> CGRect {
        guard screenWidth > 0, screenHeight > 0 else { return .zero }
        let w = CGFloat(screenWidth), h = CGFloat(screenHeight)
        let x = clamp01(screenRect.minX / w)
        let width = clamp01(screenRect.width / w)
        let height = clamp01(screenRect.height / h)
        let y = clamp01((h - screenRect.maxY) / h)   // y 翻轉：螢幕頂 → Vision 高 y
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// 一組 dirty tile 的外接框 → Vision ROI；無 tile 回 nil。
    public static func boundingROI(forTiles tiles: Set<TileXY>, grid: TileGrid) -> CGRect? {
        guard !tiles.isEmpty else { return nil }
        var union: CGRect?
        for tile in tiles {
            let rect = grid.rect(forTileX: tile.x, y: tile.y)
            union = union.map { $0.union(rect) } ?? rect
        }
        guard let bounds = union else { return nil }
        return normalizedROI(screenRect: bounds, screenWidth: grid.width, screenHeight: grid.height)
    }

    private static func clamp01(_ v: CGFloat) -> CGFloat { min(max(v, 0), 1) }
}
