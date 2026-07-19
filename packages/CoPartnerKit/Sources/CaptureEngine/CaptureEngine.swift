import Foundation
import CoreGraphics
import CoPartnerCore
// 設計：docs/design/v2_smart-capture-engine.md §B
// TODO(M1): tile 冷熱狀態機 + DYNAMIC 影片降頻（§B.6，step 19 取代目前的 .warm 佔位）
// TODO(M3): reference frame + delta 重建（§B.7）

/// 擷取引擎：吃 FrameProducer 的每幀（SCK 觀測 + per-tile hash），
/// 以 DirtyRegionResolver 融合出「這幀哪些 tile 髒了」，逐一吐成 TileEvent 串流。
/// 真幀來源（SCStream + Metal hash）為 🔒（step 18）；此處管線用假來源即可 CI 全測。
public actor CaptureEngine {
    public let grid: TileGrid
    private let resolver: DirtyRegionResolver
    private var previousHashes: [UInt64]?
    private var task: Task<Void, Never>?
    private var continuation: AsyncStream<TileEvent>.Continuation?

    public init(grid: TileGrid, thresholds: ChangeThresholds = ChangeThresholds()) {
        self.grid = grid
        self.resolver = DirtyRegionResolver(grid: grid, thresholds: thresholds)
    }

    /// 開始消費幀來源，回傳 dirty-tile 事件串流。stop() 或來源結束時串流 finish。
    public func start(from producer: FrameProducer) -> AsyncStream<TileEvent> {
        stopInternal()                       // 重入保護：先收掉上一輪
        let (stream, continuation) = AsyncStream<TileEvent>.makeStream()
        self.continuation = continuation
        self.previousHashes = nil
        task = Task { [weak self] in
            for await frame in producer.frames() {
                await self?.process(frame)
            }
            await self?.finish()             // 來源自然結束 → 收尾
        }
        return stream
    }

    public func stop() { stopInternal() }

    // MARK: - 內部

    private func process(_ frame: TileFrame) {
        let dirty: Set<TileXY>
        if let previous = previousHashes {
            dirty = resolver.resolve(frame, oldHashes: previous, newHashes: frame.hashes)
        } else {
            dirty = resolver.tiles(forDirtyRects: frame.dirtyRects)   // 首幀無前一幀可比 → 只採 dirtyRects
        }
        previousHashes = frame.hashes
        for tile in dirty {
            let index = tile.y * grid.cols + tile.x
            let dhash = frame.hashes.indices.contains(index) ? frame.hashes[index] : 0
            continuation?.yield(TileEvent(tileX: tile.x, tileY: tile.y,
                                          state: .warm,          // 佔位；真冷熱狀態機於 step 19
                                          dhash: dhash, timestamp: frame.timestamp))
        }
    }

    private func finish() {
        continuation?.finish()
        continuation = nil
    }

    private func stopInternal() {
        task?.cancel()
        task = nil
        continuation?.finish()
        continuation = nil
        previousHashes = nil
    }
}

/// 事件加權的注意力模型（ADR-0006 / §B.3.1）。
/// 注意力能量 A∈[0,1] 驅動 attention region 的大小、解析度與 FPS。
/// 點擊 = 動作起點 → 拉到峰值並立即強制高解析擷取；移動/靜置 → 隨時間衰減。
public actor AttentionModel {
    public enum Signal: Sendable, Equatable { case click, drag, scroll, keyDown, move(speed: Double), idle }

    private var energy: Double = 0          // A ∈ [0,1]
    public private(set) var center: CGPoint = .zero
    private let halfLifeSeconds = 2.0
    private var lastUpdate: Date

    /// `now` 可注入以利決定性測試（對齊 CloudRouter.EscalationPolicy.decide(_:now:)）。
    public init(now: Date = Date()) { lastUpdate = now }

    /// 目前注意力能量 A∈[0,1]（唯讀；供 UI 與測試檢視）。
    public var currentEnergy: Double { energy }

    /// 收到輸入事件時更新能量（取 max，避免被低權重事件壓低）。
    /// 回傳 true 表示呼叫端應「立即強制一次高解析擷取」（點擊時）。
    @discardableResult
    public func update(_ signal: Signal, at point: CGPoint? = nil, now: Date = Date()) -> Bool {
        decay(now: now)
        if let p = point { center = p }
        switch signal {
        case .click:           energy = 1.0; return true   // 動作起點：峰值 + 強制擷取
        case .drag:            energy = max(energy, 0.85)
        case .keyDown:         energy = max(energy, 0.8)    // 錨定 focused element（§B.4）
        case .scroll:          energy = max(energy, 0.6)
        case .move(let speed): energy = max(energy, 0.3 * (1 - min(max(speed, 0), 1))) // 快移→更低
        case .idle:            break                         // 只衰減
        }
        return false
    }

    private func decay(now: Date) {
        let dt = now.timeIntervalSince(lastUpdate); lastUpdate = now
        guard dt > 0 else { return }
        energy *= pow(0.5, dt / halfLifeSeconds)
        if energy < 0.05 { energy = 0 }
    }

    /// 把能量映射成擷取參數（門檻分帶，對應 §B.6 狀態）。
    public func captureParams(now: Date = Date()) -> (radiusPt: Double, scale: Double, fps: Double) {
        decay(now: now)
        switch energy {
        case 0.7...:     return (400, 2.0, 8)   // HOT：點擊/拖曳後窗口
        case 0.4..<0.7:  return (300, 1.0, 4)   // 升高：scroll / typing
        case 0.15..<0.4: return (250, 1.0, 2)   // WARM：剛移動過
        default:         return (0,   0.5, 0.2) // COLD：靜置 → 周邊心跳
        }
    }
}
