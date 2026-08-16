import Foundation
// 設計：v2.1 §2（L1 rollup）。決定「**何時**該把累積的 L0 行捲成一個 L1 step」的純邏輯，
// 不碰模型、不碰時鐘（`now` 一律由呼叫端注入）→ 完全確定性、CI 可測。
//
// 為什麼需要排程而不是每來一行就敘事一次：L1 要叫本地 3B 模型，成本遠高於 L0 的模板成句。
// 每個按鍵都 rollup 會把 M4 的 sub-second 預算燒光，而且「一個 step」本來就該涵蓋一小段
// 有語意的操作，不是單一鍵擊。
//
// ⚠️ 新活動的偵測**不能用行數差**，有兩個各自獨立的原因：
//   1. `EventLog.record` 會**就地修改最後一行**（同欄位連續打字合併、同向 scroll 聚合），
//      使用者狂打字時行數可以完全不動，但內容一直在變。
//   2. `EventLogFeed` 是 ring buffer，飽和後行數固定在 capacity 不再成長，舊行從頭被丟掉。
// 兩者都會讓「count 差」永久歸零，rollup 就再也不會觸發。
// 因此以 **(行數, 末行內容) 這組指紋**判斷新穎度：append 會改變其一，就地合併會改變末行，
// ring 汰換在飽和時也會改變末行。行皆帶時間戳，指紋碰撞在實務上不會發生。

/// L1 rollup 的觸發排程器。呼叫端在快照更新時呼叫 `observe`，在計時器 tick 時呼叫 `evaluate`。
public struct L1RollupScheduler: Sendable {

    /// 這次 rollup 是被什麼條件觸發的（顯示 / 測試用）。
    public enum Trigger: String, Sendable, Equatable {
        /// 切換 app：天然的 step 邊界（§2 L2 也以切 app 分段）。
        case appBoundary
        /// 累積夠多新活動。
        case lineCount
        /// 有新活動但一直沒滿量，時間到了也要出一個 step，否則慢速操作永遠等不到敘事。
        case interval
    }

    /// 累積幾筆新活動就值得叫一次模型。
    public var minNewLines: Int
    /// 有新活動時，最長多久一定 rollup 一次。
    public var maxInterval: TimeInterval
    /// 每次餵給模型的最近行數上限（step 是「一小段操作」，不是整個 session）。
    public var windowLines: Int

    // 新穎度指紋
    private var lastCount: Int = 0
    private var lastTail: String?
    // 自上次 rollup 起累積的新活動筆數
    private var credits: Int = 0
    // 這批新活動最早出現的時間（interval 觸發的基準）
    private var pendingSince: Date?
    // 是否有 rollup 正在跑
    private var inFlight = false

    public init(minNewLines: Int = 12, maxInterval: TimeInterval = 20, windowLines: Int = 40) {
        self.minNewLines = max(1, minNewLines)
        self.maxInterval = max(0, maxInterval)
        self.windowLines = max(1, windowLines)
    }

    /// 收到一份新的劇本快照。偵測到新活動就累計一筆 credit。
    /// 回傳是否偵測到新活動（測試 / 除錯用）。
    @discardableResult
    public mutating func observe(snapshot: [String], at now: Date) -> Bool {
        let tail = snapshot.last
        guard snapshot.count != lastCount || tail != lastTail else { return false }
        lastCount = snapshot.count
        lastTail = tail
        guard !snapshot.isEmpty else { return false }   // 清空/重置不算活動
        credits += 1
        if pendingSince == nil { pendingSince = now }
        return true
    }

    /// 現在該不該 rollup？該的話回觸發原因並進入 in-flight（呼叫端負責事後 `complete`）。
    /// in-flight 期間一律回 nil：模型呼叫可能數百 ms，重疊發動會浪費 3B 算力且讓結果亂序。
    public mutating func evaluate(now: Date, appChanged: Bool) -> Trigger? {
        guard !inFlight, credits > 0 else { return nil }
        let trigger: Trigger?
        if appChanged {
            trigger = .appBoundary
        } else if credits >= minNewLines {
            trigger = .lineCount
        } else if let since = pendingSince, now.timeIntervalSince(since) >= maxInterval {
            trigger = .interval
        } else {
            trigger = nil
        }
        if trigger != nil { inFlight = true }
        return trigger
    }

    /// rollup 結束（成功或失敗都要呼叫）：清空累積、解除 in-flight。
    public mutating func complete() {
        inFlight = false
        credits = 0
        pendingSince = nil
    }

    /// 這次要餵給模型的行：最近的 `windowLines` 行。
    /// 相鄰兩次 rollup 的視窗**可以重疊**——step 描述的是一小段時間跨度，
    /// 給模型一點前文比硬切乾淨更能產出連貫的敘述。
    public func window(of snapshot: [String]) -> [String] {
        Array(snapshot.suffix(windowLines))
    }

    /// 目前累積的新活動筆數（測試 / 除錯用）。
    public var pendingCredits: Int { credits }
    /// 是否有 rollup 正在跑（測試 / 除錯用）。
    public var isRollupInFlight: Bool { inFlight }
}
