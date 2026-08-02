import Foundation
// 設計：docs/design/v2_smart-capture-engine.md §C.4/§G。串 step 35 熱圖與 step 55 遮罩：
// 遮罩 tile 永不被 reinforce（出口三）；summary 永不指向遮罩區（top 被遮 → 回退次熱未遮、全遮回空）。
// step 35 的「只存聚合權重 O(tiles)」不變式照舊——本 guard 只在寫入/讀出兩端加遮罩閘。

public enum AttentionPrivacyGuard {
    /// 遮罩 tile → no-op；否則正常 reinforce（TileMaskPolicy 出口三的落地）。
    public static func reinforceIfAllowed(_ heatmap: inout AttentionHeatmap,
                                          tile: TileXY, weight: Double, at now: Date,
                                          mask: SensitiveTileMask) {
        guard TileMaskPolicy.mayReinforceAttention(masked: mask.isMasked(tile, at: now)) else { return }
        heatmap.reinforce(tile: tile, weight: weight, at: now)
    }

    /// 未被遮罩的熱門 tile（高→低），供 summary / envelope attention_summary 使用。
    public static func visibleTopTiles(_ heatmap: AttentionHeatmap,
                                       mask: SensitiveTileMask, at now: Date, _ n: Int) -> [TileXY] {
        guard n > 0 else { return [] }
        return Array(heatmap.topTiles(heatmap.storedTileCount)
            .filter { !mask.isMasked($0, at: now) }
            .prefix(n))
    }

    /// summary 永不指向遮罩區：取最熱的未遮 tile；全遮 / 無熱 → 空字串。
    public static func sanitizedSummary(_ heatmap: AttentionHeatmap,
                                        mask: SensitiveTileMask, at now: Date) -> String {
        guard let top = visibleTopTiles(heatmap, mask: mask, at: now, 1).first else { return "" }
        return "注意力集中於 \(heatmap.grid.cols)×\(heatmap.grid.rows) 網格的 tile (\(top.x), \(top.y)) 一帶"
    }
}
