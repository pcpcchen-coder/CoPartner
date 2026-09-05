import CoreGraphics
// 設計：§G 縱深五層第 2 層（tile 遮罩）延伸到**出境**這條路徑上。step 58。
//
// `SensitiveTileMask` 算得出「哪些 tile 是敏感的」，但它原本只服務三個出口
// （OCR / 持久化 / 熱圖，見 `TileMaskPolicy`）。送截圖出境是**第四個出口**，
// 而它需要的形狀不同：不是「這個 tile 能不能用」，是「這張圖上哪幾塊要塗黑」。
//
// 這裡只做幾何，不做決策——決策在 `ScreenshotEgressPolicy`（CloudRouter）。
// 分開的理由與 `EgressGate` 用注入 scrubber 是同一個：**不讓出境層依賴擷取層**。
public enum ScreenshotRedaction {

    /// 敏感 tile → **正規化矩形**（0…1，原點左上、y 向下，與影像座標同向）。
    ///
    /// 回正規化而不是像素：送出去的圖幾乎一定被縮放過，而縮放比例在這一層是未知的。
    /// 回像素等於要求呼叫端自己換算，那正是 `ScreenCoordinateMapper` 那一課裡
    /// 「算錯不會報錯」的同一個坑——塗錯位置的後果是**該遮的沒遮**，而且看不出來。
    public static func normalizedRects(for tiles: Set<TileXY>, in grid: TileGrid) -> [CGRect] {
        let width = CGFloat(grid.width), height = CGFloat(grid.height)
        guard width > 0, height > 0 else { return [] }
        // 排序讓輸出穩定：順序不穩定的話，測試與 diff 都會變得沒辦法讀。
        return tiles.sorted { ($0.y, $0.x) < ($1.y, $1.x) }.map { tile in
            let r = grid.rect(forTileX: tile.x, y: tile.y)
            return CGRect(x: r.minX / width, y: r.minY / height,
                          width: r.width / width, height: r.height / height)
        }
    }

    /// 正規化矩形（**左上原點、y 向下**，影像座標）→ 目標像素矩形
    /// （**左下原點、y 向上**，CoreGraphics bitmap context 的座標系）。
    ///
    /// 這一步是整條遮罩鏈裡最容易靜默出錯的地方：兩個座標系差一個 y 翻轉，
    /// 而翻轉錯的後果是**塗黑塗到鏡像的位置**——密碼欄在畫面上半部，黑塊出現在下半部，
    /// 該遮的地方原封不動地送出去，而圖片本身看起來完全正常（上面就是有一塊黑）。
    ///
    /// 所以它不寫在繪圖的膠水裡，寫在這裡並且有測試釘住「上面的要對到上面」。
    public static func bottomLeftPixelRects(_ normalized: [CGRect],
                                            targetSize: CGSize) -> [CGRect] {
        let w = targetSize.width, h = targetSize.height
        guard w > 0, h > 0, w.isFinite, h.isFinite else { return [] }
        return normalized.map { r in
            CGRect(x: r.minX * w,
                   // 翻轉：正規化的 maxY（下緣）變成 CG 的 minY（下緣距離底部的高度）。
                   y: (1 - r.maxY) * h,
                   width: r.width * w,
                   height: r.height * h)
        }
    }

    /// 敏感 tile 佔全畫面的比例（0…1）。格線退化時回 1——
    /// **算不出來就當成「整片敏感」**，讓下游的上限規則自動擋掉。
    /// 回 0 會讓退化的格線看起來像「完全乾淨」，那是最糟的預設值。
    public static func maskedFraction(for tiles: Set<TileXY>, in grid: TileGrid) -> Double {
        let total = grid.cols * grid.rows
        guard total > 0, grid.width > 0, grid.height > 0 else { return 1 }
        return Double(tiles.count) / Double(total)
    }
}
