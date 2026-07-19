import Foundation
import CoreVideo
@preconcurrency import ScreenCaptureKit
// 🔒 真機膠水：FrameProducer 的真實作。ScreenCaptureSource（SCStream）每幀的 CVPixelBuffer
// 經 TileHashComputer（Metal）算 per-tile hash → TileFrame 串流。需 Screen Recording 權限；
// 實際擷取 / hash 正確性 / 效能於 step 18 真機驗（CI 只保證編譯）。

public final class SCKFrameProducer: FrameProducer, @unchecked Sendable {
    private let hasher: TileHashComputer
    private let source: ScreenCaptureSource
    private let stream: AsyncStream<TileFrame>
    private let continuation: AsyncStream<TileFrame>.Continuation

    public init(grid: TileGrid) throws {
        let hasher = try TileHashComputer(grid: grid)
        self.hasher = hasher
        let (stream, continuation) = AsyncStream<TileFrame>.makeStream(bufferingPolicy: .bufferingNewest(2))
        self.stream = stream
        self.continuation = continuation
        // handler 在 SCK sample queue（單一序列）呼叫：算 hash → 打包 TileFrame → yield。
        self.source = ScreenCaptureSource { info, pixelBuffer in
            let hashes = (try? hasher.computeHashes(from: pixelBuffer)) ?? []
            guard !hashes.isEmpty else { return }
            continuation.yield(TileFrame(status: info.status,
                                         dirtyRects: info.dirtyRects,
                                         contentRect: info.contentRect,
                                         app: nil,   // per-app override 之後接（需前景 app 名）
                                         hashes: hashes,
                                         timestamp: Date()))
        }
    }

    /// filter / configuration 由呼叫端依 SCShareableContent 的 display 組出（見 AppCoordinator）。
    public func start(filter: SCContentFilter, configuration: SCStreamConfiguration) throws {
        try source.start(filter: filter, configuration: configuration)
    }

    public func frames() -> AsyncStream<TileFrame> { stream }

    public func stop() {
        source.stop()
        continuation.finish()
    }
}
