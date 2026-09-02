import Foundation
import CoPartnerCore
// 把 CaptureEngine 的 TileEvent 流聚合成選單列可顯示的「擷取活動摘要」。純值、可測。
// step 16 的協調邏輯（真擷取來源 SCKFrameProducer 於 step 18 真機接上）。

public struct CaptureActivity: Sendable, Equatable {
    /// 消費端**實際收到**的事件數。
    public private(set) var totalDirtyEvents: Int = 0
    /// 引擎**產生**的事件數，由外部填（`CaptureEngine.producedEvents`）。
    ///
    /// 為什麼要分成兩個數字：事件串流從 step 53.7 起是**有界**的，消費端跟不上時
    /// 舊事件會被丟掉。只記「收到幾個」的話，畫面上那個數字會在消費端塞車時
    /// 靜默地變小，而那正是最需要看見的時候。
    public var producedEvents: Int = 0
    public private(set) var lastTile: TileXY?
    public init() {}

    public mutating func record(_ event: TileEvent) {
        totalDirtyEvents += 1
        lastTile = TileXY(x: event.tileX, y: event.tileY)
    }

    /// 被緩衝丟棄的事件數。**大於 0 就代表消費端跟不上產生端**——
    /// 這正是記憶體診斷要找的訊號，所以它要顯示出來而不是藏起來。
    public var droppedEvents: Int { max(0, producedEvents - totalDirtyEvents) }

    /// 選單列一行摘要。
    public var summary: String {
        let produced = max(producedEvents, totalDirtyEvents)
        guard produced > 0 else { return "螢幕擷取：尚無 tile 變動" }
        let last = lastTile.map { "(\($0.x),\($0.y))" } ?? "-"
        let dropped = droppedEvents > 0 ? "，緩衝丟棄 \(droppedEvents)" : ""
        return "螢幕擷取：\(produced) 次變動，最新 tile \(last)\(dropped)"
    }
}
