import Foundation
import CoreGraphics
// 一幀縮到 CaptureEngine 需要的東西：SCK 觀測（FrameInfoProviding）+ 該幀 per-tile hash。
// 抽 FrameProducer 協定讓「幀從哪來、hash 怎麼算」與 CaptureEngine 的融合邏輯解耦——
// 真來源（ScreenCaptureSource + TileHashComputer）是 🔒，假來源讓管線可完整 CI 測試。

/// 一幀：SCK 觀測 + 該幀所有 tile 的 dHash（index = y*cols + x）。
public struct TileFrame: FrameInfoProviding, Sendable {
    public var status: FrameStatus
    public var dirtyRects: [CGRect]
    public var contentRect: CGRect
    public var app: String?          // 該幀前景 app（供 per-app override 判 DYNAMIC）
    public var hashes: [UInt64]
    public var timestamp: Date
    public init(status: FrameStatus = .complete,
                dirtyRects: [CGRect] = [],
                contentRect: CGRect = .zero,
                app: String? = nil,
                hashes: [UInt64],
                timestamp: Date) {
        self.status = status
        self.dirtyRects = dirtyRects
        self.contentRect = contentRect
        self.app = app
        self.hashes = hashes
        self.timestamp = timestamp
    }
}

/// 幀來源：產出 TileFrame 串流。真實作 🔒（ScreenCaptureSource + TileHashComputer，step 18）；
/// 測試用假來源餵 canned frames。
public protocol FrameProducer: Sendable {
    func frames() -> AsyncStream<TileFrame>
    func stop()
}
