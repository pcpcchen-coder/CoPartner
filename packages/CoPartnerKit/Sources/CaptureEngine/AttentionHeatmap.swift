import Foundation
// 設計：docs/design/v2_smart-capture-engine.md §C.4 / §G。tile grid 衰減式熱圖。
// **隱私硬約束**：只存每 tile 聚合衰減權重 + 單一 lastDecay 時戳，**不存原始座標時序**；
// 權重低於 epsilon 即 TTL 淘汰。產 attention_summary 自然語言轉述（餵 ContextEnvelope，v2.1 §4）。

public struct AttentionHeatmap: Sendable {
    public let grid: TileGrid
    public let halfLife: TimeInterval          // 權重衰減半衰期（秒）
    private var weights: [TileXY: Double] = [:]
    private var lastDecay: Date?
    private let epsilon: Double                 // 低於此值視為 0（TTL 淘汰）

    public init(grid: TileGrid, halfLife: TimeInterval = 20, epsilon: Double = 0.01) {
        self.grid = grid
        self.halfLife = max(0.0001, halfLife)
        self.epsilon = max(0, epsilon)
    }

    /// 先把既有權重衰減到 time，再對該 tile 加權（維持「只存聚合」不變式）。
    public mutating func reinforce(tile: TileXY, weight: Double = 1, at time: Date) {
        decay(to: time)
        weights[tile, default: 0] += max(0, weight)
    }

    /// 依距 lastDecay 的時間指數衰減全體權重；低於 epsilon 者淘汰（TTL）。
    public mutating func decay(to now: Date) {
        defer { lastDecay = now }
        guard let last = lastDecay else { return }
        let elapsed = now.timeIntervalSince(last)
        guard elapsed > 0 else { return }
        let factor = pow(0.5, elapsed / halfLife)
        for (tile, w) in weights {
            let nw = w * factor
            if nw < epsilon { weights.removeValue(forKey: tile) }
            else { weights[tile] = nw }
        }
    }

    public func weight(for tile: TileXY) -> Double { weights[tile] ?? 0 }

    /// 權重最高的前 n 個 tile（高→低）。
    public func topTiles(_ n: Int) -> [TileXY] {
        guard n > 0 else { return [] }
        return weights.sorted { $0.value > $1.value }.prefix(n).map { $0.key }
    }

    /// 內部僅存的 tile 數（隱私不變式驗證用：應為 O(tiles) 非 O(events)）。
    public var storedTileCount: Int { weights.count }

    /// 自然語言轉述（熱區描述）；無明顯熱區回空字串。
    public func summary() -> String {
        guard let top = weights.max(by: { $0.value < $1.value }), top.value >= epsilon else { return "" }
        return "注意力集中於 \(grid.cols)×\(grid.rows) 網格的 tile (\(top.key.x), \(top.key.y)) 一帶"
    }
}
