import Foundation
import CoreGraphics
import CoPartnerCore
// 設計：docs/design/v2_smart-capture-engine.md §B
// reference frame + delta 重建：ReferenceDeltaStore 已於 step 31 完成（M3）；接入本引擎的持久化 wiring 待 M3 真機段

/// 擷取引擎：吃 FrameProducer 的每幀（SCK 觀測 + per-tile hash），
/// 以 DirtyRegionResolver 融合出「這幀哪些 tile 髒了」，經 per-tile 冷熱狀態機（§B.6）
/// 賦予 COLD/WARM/HOT/DYNAMIC 狀態，逐一吐成 TileEvent 串流。
/// 真幀來源（SCStream + Metal hash）為 🔒（step 18）；此處管線用假來源即可 CI 全測。
public actor CaptureEngine {
    public let grid: TileGrid
    public private(set) var overrides: CaptureOverrides
    private let resolver: DirtyRegionResolver
    private let stateConfig: TileStateMachine.Config
    private var previousHashes: [UInt64]?
    private var tileStates: [TileXY: TileStateMachine] = [:]
    private var tilePeriodicity: [TileXY: PeriodicityDetector] = [:]
    private var task: Task<Void, Never>?
    private var continuation: AsyncStream<TileEvent>.Continuation?

    public init(grid: TileGrid,
                thresholds: ChangeThresholds = ChangeThresholds(),
                overrides: CaptureOverrides = CaptureOverrides(),
                stateConfig: TileStateMachine.Config = .init()) {
        self.grid = grid
        self.resolver = DirtyRegionResolver(grid: grid, thresholds: thresholds)
        self.overrides = overrides
        self.stateConfig = stateConfig
    }

    /// 更新 per-app override（如把某 app 標為 neverDynamic）。
    public func setOverrides(_ overrides: CaptureOverrides) { self.overrides = overrides }

    /// 事件串流的緩衝上限。
    ///
    /// **原本沒有指定，也就是無上限**——而同一條管線上游的 `SCKFrameProducer` 卻明確用了
    /// `.bufferingNewest(2)`。同一條管線兩種策略，看起來是疏漏而非取捨，而它從
    /// step 53.7 的記憶體診斷第一天就被列為嫌疑。
    ///
    /// 真機日誌把它變成主要嫌疑：觀察中記憶體以約 +100 MB/小時線性成長，**跟時間走、
    /// 不跟 step 走**，而這條串流唯一的消費者是 `AppCoordinator` 裡一個 `@MainActor`
    /// 的計數器——每個事件都要跳一次 MainActor，而 MainActor 同時還在跑 UI、OCR、敘事。
    /// 產生端（幀處理）不會等消費端，於是跟不上的部分就堆在這個無上限的緩衝裡。
    /// 一次真機工作階段曾累積 143515 個事件。
    ///
    /// 選 `.bufferingNewest`：舊的 tile 事件對唯一的消費者（一個計數器 + 最後一個 tile）
    /// 沒有價值，新的才有。丟掉的數量會**顯示在選單上**（`CaptureActivity.droppedEvents`）
    /// ——靜默丟事件會讓「消費端塞車」這個訊號消失，而那正是要找的東西。
    private static let eventBufferLimit = 64

    /// 引擎**產生**的事件總數（丟棄之前）。畫面上顯示的次數要用這個，
    /// 不是消費端收到的數量——否則塞車時那個數字會靜默變小。
    public private(set) var producedEvents = 0

    /// 開始消費幀來源，回傳 dirty-tile 事件串流。stop() 或來源結束時串流 finish。
    public func start(from producer: FrameProducer) -> AsyncStream<TileEvent> {
        stopInternal()                       // 重入保護：先收掉上一輪
        producedEvents = 0
        let (stream, continuation) = AsyncStream<TileEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(Self.eventBufferLimit))
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
        let previous = previousHashes
        let dirty: Set<TileXY>
        if let previous {
            dirty = resolver.resolve(frame, oldHashes: previous, newHashes: frame.hashes)
        } else {
            dirty = resolver.tiles(forDirtyRects: frame.dirtyRects)   // 首幀無前一幀可比 → 只採 dirtyRects
        }
        let allowDynamic = overrides.allowsDynamic(app: frame.app ?? "")

        for tile in dirty {
            let index = tile.y * grid.cols + tile.x
            let magnitude = changeMagnitude(at: index, previous: previous, current: frame.hashes)
            var periodicity = tilePeriodicity[tile] ?? PeriodicityDetector()
            let periodic = periodicity.record(frame.timestamp)
            tilePeriodicity[tile] = periodicity
            var machine = tileStates[tile] ?? TileStateMachine(config: stateConfig)
            let state = machine.update(change: magnitude, at: frame.timestamp,
                                       periodic: periodic && allowDynamic, hasAXText: false)
            tileStates[tile] = machine
            let dhash = frame.hashes.indices.contains(index) ? frame.hashes[index] : 0
            producedEvents += 1              // 在 yield **之前**加：緩衝丟棄不該讓計數失真
            continuation?.yield(TileEvent(tileX: tile.x, tileY: tile.y, state: state,
                                          dhash: dhash, timestamp: frame.timestamp))
        }

        // 冷卻未變動的已追蹤 tile；轉冷即移除（bounded 記憶體）。
        for tile in Array(tileStates.keys) where !dirty.contains(tile) {
            var machine = tileStates[tile]!
            _ = machine.update(change: .none, at: frame.timestamp, periodic: false, hasAXText: false)
            if machine.state == .cold {
                tileStates[tile] = nil
                tilePeriodicity[tile] = nil
            } else {
                tileStates[tile] = machine
            }
        }
        previousHashes = frame.hashes
    }

    /// 某 tile 這幀的變動幅度。首幀 / 索引缺 → large；在 dirty set 但 hash 未變（rect 觸發）→ small。
    private func changeMagnitude(at index: Int, previous: [UInt64]?, current: [UInt64]) -> ChangeMagnitude {
        guard let previous, previous.indices.contains(index), current.indices.contains(index) else {
            return .large
        }
        let magnitude = TileHashDiff.classify(old: previous[index], new: current[index],
                                              thresholds: resolver.thresholds)
        return magnitude == .none ? .small : magnitude
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
        tileStates.removeAll()
        tilePeriodicity.removeAll()
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

    /// 依當前能量回傳三層擷取金字塔（§B.5：焦點 / 周邊 / 概覽）。
    public func capturePyramid(now: Date = Date()) -> CapturePyramid {
        decay(now: now)
        return CapturePyramid.forEnergy(energy)
    }
}
