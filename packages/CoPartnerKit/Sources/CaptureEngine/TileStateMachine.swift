import Foundation
import CoPartnerCore
// 設計：§B.6（tile 冷熱狀態機）+ §L（AX 文字 tile 不套 DYNAMIC）。純狀態轉換、CI 可測。
// 吃 step 12 的 ChangeMagnitude 時間序列 + step 20 的 periodic 判定，輸出 TileEvent.State。

public struct TileStateMachine: Sendable, Equatable {
    public struct Config: Sendable, Equatable {
        public var hotThreshold: Int        // 連續變動達此幀數 → HOT
        public var coldAfter: TimeInterval  // 距最後變動超過此秒數 → COLD（否則 WARM）
        public init(hotThreshold: Int = 4, coldAfter: TimeInterval = 2.0) {
            self.hotThreshold = max(1, hotThreshold); self.coldAfter = coldAfter
        }
    }

    public private(set) var state: TileEvent.State = .cold
    public var config: Config
    private var consecutiveChanges = 0
    private var lastChangeAt: Date?

    public init(config: Config = Config()) { self.config = config }

    /// 餵一幀的變動幅度 → 新狀態。
    /// - periodic: 此 tile 變動是否規律高頻（step 20 判定）。
    /// - hasAXText: 該區可取得 AX 文字 → 封頂 HOT，永不 DYNAMIC（§L）。
    @discardableResult
    public mutating func update(change: ChangeMagnitude, at now: Date,
                                periodic: Bool, hasAXText: Bool) -> TileEvent.State {
        guard change != .none else {
            consecutiveChanges = 0
            if let last = lastChangeAt, now.timeIntervalSince(last) < config.coldAfter {
                state = .warm     // 剛還在動，現在停了 → 溫
            } else {
                state = .cold     // 久未動 → 冷
            }
            return state
        }
        consecutiveChanges += 1
        lastChangeAt = now
        let sustained = consecutiveChanges >= config.hotThreshold
        if sustained && periodic && !hasAXText {
            state = .dynamic      // 規律高頻 + 非文字 → 影片
        } else if sustained {
            state = .hot
        } else {
            state = .warm
        }
        return state
    }
}
