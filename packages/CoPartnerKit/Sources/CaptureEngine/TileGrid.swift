import CoreGraphics
// 設計：docs/design/v2_smart-capture-engine.md §B.2（切 tile、只對 dirty tile 細看）
// 純幾何換算：螢幕座標 ↔ tile 索引。供 dirty-rect 對應與 Metal hash 定址共用。純邏輯、CI 可測。

/// 一個 tile 的格線座標（左上為原點，x 向右、y 向下）。
public struct TileXY: Sendable, Equatable, Hashable {
    public let x: Int
    public let y: Int
    public init(x: Int, y: Int) { self.x = x; self.y = y }
}

/// 把 width×height 的平面切成 tileSize×tileSize 的格子。
public struct TileGrid: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let tileSize: Int

    public init(width: Int, height: Int, tileSize: Int = 128) {
        self.width = max(0, width)
        self.height = max(0, height)
        self.tileSize = max(1, tileSize)          // 保底，避免除以 0
    }

    /// 欄數 / 列數（向上取整，最後一格可能不滿）。
    public var cols: Int { (width + tileSize - 1) / tileSize }
    public var rows: Int { (height + tileSize - 1) / tileSize }

    /// 點落在哪個 tile（超出範圍會夾到邊界格；邊界像素屬「下一格」）。
    public func tileIndex(for point: CGPoint) -> TileXY {
        let tx = Int((point.x / CGFloat(tileSize)).rounded(.down))
        let ty = Int((point.y / CGFloat(tileSize)).rounded(.down))
        return TileXY(x: clampCol(tx), y: clampRow(ty))
    }

    /// rect 覆蓋到的所有 tile（夾到格線內，不越界）。空/退化 rect 回空陣列。
    public func tiles(overlapping rect: CGRect) -> [TileXY] {
        guard cols > 0, rows > 0 else { return [] }
        let firstCol = clampCol(Int((rect.minX / CGFloat(tileSize)).rounded(.down)))
        let lastCol  = clampCol(Int((rect.maxX / CGFloat(tileSize)).rounded(.up)) - 1)
        let firstRow = clampRow(Int((rect.minY / CGFloat(tileSize)).rounded(.down)))
        let lastRow  = clampRow(Int((rect.maxY / CGFloat(tileSize)).rounded(.up)) - 1)
        guard lastCol >= firstCol, lastRow >= firstRow else { return [] }
        var result: [TileXY] = []
        for ty in firstRow...lastRow {
            for tx in firstCol...lastCol {
                result.append(TileXY(x: tx, y: ty))
            }
        }
        return result
    }

    /// 某 tile 的螢幕矩形（邊緣 tile 會被夾到螢幕邊界，可能不滿一格）。
    public func rect(forTileX x: Int, y: Int) -> CGRect {
        let ox = x * tileSize
        let oy = y * tileSize
        let w = max(0, min(tileSize, width - ox))
        let h = max(0, min(tileSize, height - oy))
        return CGRect(x: ox, y: oy, width: w, height: h)
    }

    private func clampCol(_ c: Int) -> Int { min(max(c, 0), max(0, cols - 1)) }
    private func clampRow(_ r: Int) -> Int { min(max(r, 0), max(0, rows - 1)) }
}
