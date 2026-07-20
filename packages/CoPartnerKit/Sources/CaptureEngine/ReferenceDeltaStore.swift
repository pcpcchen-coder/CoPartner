import Foundation
// 設計：docs/design/v2_smart-capture-engine.md §B.7（reference frame + delta / I·P-frame）。
// 維護壓縮 reference（I-frame）＋ 一串 delta（P-frame：只帶變動 tile）；需完整畫面時 reference ⊕ deltas 重建。
// 純簿記、CI 可測：tile 內容以不透明識別子（hash + 可選 payload）代表，不需真像素。
// 真像素無損 round-trip 與磁碟持久化 🔒 step 36。資料正確性風險最高——含 grid 不符防禦（防靜默損毀）。

/// 一個 tile 的內容識別（dHash + 可選壓縮位元組）；hash 當去重 key。
public struct TileCell: Sendable, Equatable {
    public let hash: UInt64
    public let payload: Data?
    public init(hash: UInt64, payload: Data? = nil) {
        self.hash = hash
        self.payload = payload
    }
}

/// 一張可重建的完整畫面快照（reference 或重建結果）。
public struct FrameSnapshot: Sendable, Equatable {
    public let grid: TileGrid
    public var tiles: [TileXY: TileCell]
    public init(grid: TileGrid, tiles: [TileXY: TileCell]) {
        self.grid = grid
        self.tiles = tiles
    }
}

/// 一個 delta（P-frame）：只帶變動 tile，附自身 grid 供一致性檢查。
public struct DeltaFrame: Sendable, Equatable {
    public let grid: TileGrid
    public let changed: [TileXY: TileCell]
    public init(grid: TileGrid, changed: [TileXY: TileCell]) {
        self.grid = grid
        self.changed = changed
    }
}

public enum ReferenceDeltaError: Error, Equatable {
    case noReference        // 尚未設 reference 就 append delta
    case gridMismatch       // delta 的 grid 與 reference 不符
}

/// reference（I-frame）+ 一串 delta（P-frame）的壓縮存放；重建＝reference 疊上依序的 delta（後寫覆蓋）。
public struct ReferenceDeltaStore: Sendable {
    private var reference: FrameSnapshot?
    private var deltas: [DeltaFrame] = []

    public init() {}

    public var deltaCount: Int { deltas.count }
    public var hasReference: Bool { reference != nil }

    /// 設新 reference（re-baseline）：清掉既有 delta 串。
    public mutating func setReference(_ frame: FrameSnapshot) {
        reference = frame
        deltas.removeAll(keepingCapacity: true)
    }

    /// 追加一個 delta；無 reference 或 grid 不符 → throws（防重建靜默損毀）。
    public mutating func appendDelta(_ delta: DeltaFrame) throws {
        guard let ref = reference else { throw ReferenceDeltaError.noReference }
        guard delta.grid == ref.grid else { throw ReferenceDeltaError.gridMismatch }
        deltas.append(delta)
    }

    /// 累積 delta 覆蓋率：所有 delta 變動 tile 的**聯集** ÷ 總格數（供 step 34 re-baseline 觸發）。
    public var pendingDeltaCoverage: Double {
        guard let ref = reference else { return 0 }
        let total = ref.grid.cols * ref.grid.rows
        guard total > 0 else { return 0 }
        var union: Set<TileXY> = []
        for d in deltas { union.formUnion(d.changed.keys) }
        return Double(union.count) / Double(total)
    }

    /// 重建到第 idx 個 delta（含）為止；idx < 0 → 只回 reference。
    public func reconstruct(throughDeltaIndex idx: Int) -> FrameSnapshot {
        guard var snap = reference else {
            return FrameSnapshot(grid: TileGrid(width: 0, height: 0), tiles: [:])
        }
        guard idx >= 0, !deltas.isEmpty else { return snap }
        let upper = min(idx, deltas.count - 1)
        for i in 0...upper {
            for (xy, cell) in deltas[i].changed { snap.tiles[xy] = cell }
        }
        return snap
    }

    /// 重建完整畫面（套用所有 delta）。
    public func reconstruct() -> FrameSnapshot {
        reconstruct(throughDeltaIndex: deltas.count - 1)
    }
}
