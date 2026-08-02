import Foundation
import CoreGraphics
// 設計：docs/design/v2_smart-capture-engine.md §G（tile 級遮罩）。敏感區域 → 對應 tile
// **不 OCR、不持久化、不進熱圖**，只記「此處有敏感輸入」。漏遮＝PII 外洩，故 **sticky fail-closed**：
// region 消失後 tile 續遮 stickySeconds 才解除（焦點暫移 / AX 抖動不得造成漏遮窗口）。
// 純簿記、CI 可測；真 kAXSecureTextField 偵測與 URL/OCR 啟發式接線 🔒 step 58。

public struct SensitiveRegion: Sendable, Equatable {
    public enum Reason: String, Sendable, Equatable { case secureField, piiText, heuristic }
    public let rect: CGRect
    public let reason: Reason
    public init(rect: CGRect, reason: Reason) {
        self.rect = rect
        self.reason = reason
    }
}

public struct SensitiveTileMask: Sendable {
    public let grid: TileGrid
    public let stickySeconds: TimeInterval
    private var lastSeen: [TileXY: Date] = [:]   // tile → 最後一次被敏感 region 覆蓋的時間

    public init(grid: TileGrid, stickySeconds: TimeInterval = 5) {
        self.grid = grid
        self.stickySeconds = max(0, stickySeconds)
    }

    /// 以當前敏感 region 更新遮罩：覆蓋到的 tile 刷新 lastSeen=now。
    /// 消失的 tile **不立刻回收**——由 isMasked 的 sticky 窗判定（fail-closed）。順手修剪早過窗的紀錄。
    public mutating func update(regions: [SensitiveRegion], at now: Date) {
        for region in regions {
            for tile in grid.tiles(overlapping: region.rect) {
                lastSeen[tile] = now
            }
        }
        let cutoff = now.addingTimeInterval(-stickySeconds)
        lastSeen = lastSeen.filter { $0.value >= cutoff }
    }

    /// 該 tile 目前是否遮罩（sticky 窗內）。time-based——即使沒再 update 也會自然到期（fail-safe 讀路徑）。
    public func isMasked(_ tile: TileXY, at now: Date) -> Bool {
        guard let seen = lastSeen[tile] else { return false }
        return now.timeIntervalSince(seen) <= stickySeconds
    }

    public func maskedTiles(at now: Date) -> Set<TileXY> {
        let cutoff = now.addingTimeInterval(-stickySeconds)
        return Set(lastSeen.filter { $0.value >= cutoff }.keys)
    }
}

/// 遮罩的**三出口單點鎖**：OCR/AX 文字、持久化、注意力熱圖三個決策都從這裡出——
/// 未來新增任何資料出口都必經此政策點，防「加了新出口忘了接遮罩」的靜默洩漏。
public enum TileMaskPolicy {
    /// 出口一：文字來源。遮罩 → 一律 .skip（不論 base 想做什麼）。
    public static func effectiveTextSource(masked: Bool, base: TextSource) -> TextSource {
        masked ? .skip : base
    }
    /// 出口二：持久化。遮罩 → 不存。
    public static func mayPersist(masked: Bool) -> Bool { !masked }
    /// 出口三：注意力熱圖。遮罩 → 不 reinforce。
    public static func mayReinforceAttention(masked: Bool) -> Bool { !masked }
}
