import Foundation
import CoPartnerCore
// 把 CaptureEngine 的 TileEvent 流聚合成選單列可顯示的「擷取活動摘要」。純值、可測。
// step 16 的協調邏輯（真擷取來源 SCKFrameProducer 於 step 18 真機接上）。

public struct CaptureActivity: Sendable, Equatable {
    public private(set) var totalDirtyEvents: Int = 0
    public private(set) var lastTile: TileXY?
    public init() {}

    public mutating func record(_ event: TileEvent) {
        totalDirtyEvents += 1
        lastTile = TileXY(x: event.tileX, y: event.tileY)
    }

    /// 選單列一行摘要。
    public var summary: String {
        guard totalDirtyEvents > 0 else { return "螢幕擷取：尚無 tile 變動" }
        let last = lastTile.map { "(\($0.x),\($0.y))" } ?? "-"
        return "螢幕擷取：\(totalDirtyEvents) 次變動，最新 tile \(last)"
    }
}
