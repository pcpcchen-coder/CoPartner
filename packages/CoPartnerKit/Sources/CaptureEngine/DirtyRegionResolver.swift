import CoreGraphics
// 設計：§B.1（SCK dirtyRects 主訊號 + Metal hash 驗證）+ ADR-0003（hash 為 ground truth）
// 純融合邏輯（CI 可測）。真 SCStream 擷取在 ScreenCaptureSource（🔒）。

/// SCK 每幀狀態（鏡射 SCFrameStatus）。§B.1：`.idle` 常被誤報，不可用來「證明沒變」。
public enum FrameStatus: Sendable, Equatable {
    case complete, idle, blank, suspended, started, stopped
}

/// 一幀的 SCK 觀測（由 ScreenCaptureSource 從 attachments 解出，或測試餵入）。
public protocol FrameInfoProviding {
    var status: FrameStatus { get }
    var dirtyRects: [CGRect] { get }
    var contentRect: CGRect { get }
}

/// 融合 SCK dirtyRects 與 per-tile hash，產出「這幀哪些 tile 真的髒了」。
/// 原則（§B.1 / ADR-0003）：
///  - **hash 是 ground truth**：任何 hash 變動的 tile 都算髒，不因 status=`.idle` 或 dirtyRects 為空而漏報。
///  - **dirtyRects 是 SCK 的正向候選**，一併採信（取聯集）——偏向多報 > 漏報（漏報＝顯示過期內容，較糟）。
///  - **刻意不以 contentRect.origin 平移 dirtyRects**：SCK 契約下 dirtyRects 已是內容座標，
///    且 Sequoia 15.6.1 的 contentRect.x=48 偽偏移反而破壞對齊；越界 rect 由 grid 邊界夾持吸收。
///    （真實座標慣例於 step 18 真機最終確認。）
public struct DirtyRegionResolver: Sendable {
    public let grid: TileGrid
    public var thresholds: ChangeThresholds

    public init(grid: TileGrid, thresholds: ChangeThresholds = ChangeThresholds()) {
        self.grid = grid
        self.thresholds = thresholds
    }

    /// dirtyRects → tile 集合（夾到格線內，越界不產生幽靈 tile）。
    public func tiles(forDirtyRects rects: [CGRect]) -> Set<TileXY> {
        var result: Set<TileXY> = []
        for rect in rects {
            for tile in grid.tiles(overlapping: rect) { result.insert(tile) }
        }
        return result
    }

    /// hash 有變動（≠ `.none`）的 tile。index = y*cols + x；陣列長度不符（無有效比較）回空。
    public func hashChangedTiles(oldHashes: [UInt64], newHashes: [UInt64]) -> Set<TileXY> {
        let expected = grid.cols * grid.rows
        guard expected > 0, oldHashes.count == expected, newHashes.count == expected else { return [] }
        var result: Set<TileXY> = []
        for i in 0..<expected where
            TileHashDiff.classify(old: oldHashes[i], new: newHashes[i], thresholds: thresholds) != .none {
            result.insert(TileXY(x: i % grid.cols, y: i / grid.cols))
        }
        return result
    }

    /// 權威 dirty tile 集合 ＝ dirtyRects 對應 tile ∪ hash 變動 tile。
    /// status 刻意不參與抑制（§B.1：`.idle` 不可信）。
    public func resolve(_ info: FrameInfoProviding,
                        oldHashes: [UInt64], newHashes: [UInt64]) -> Set<TileXY> {
        tiles(forDirtyRects: info.dirtyRects)
            .union(hashChangedTiles(oldHashes: oldHashes, newHashes: newHashes))
    }
}
