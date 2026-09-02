import Foundation
// 診斷工具（step 53.7 / handoff §7.6.6）：記憶體用量的成長曲線。
//
// ## 為什麼是「開選單時取樣」而不是定時器
//
// 這個工具最早是為了查「閒置時記憶體一直漲」而做的，也就是說**要量的正是閒置路徑**。
// 在閒置路徑上裝一個每 N 秒醒來的定時器，等於在被觀察的對象裡加一個新的觀察者：
// 它自己會配置、會讓 runloop 醒來、會改變我們想量的那條曲線。
//
// 改成「每次打開選單時取一個樣」：背景成本**恰好是零**，而使用者本來就會不時打開
// 選單看一眼，那些時間點自然就串成一條曲線。代價是取樣間隔不規則。
//
// ## 兩次被真機資料修正的判讀方式
//
// 這個型別的難處不在於記數字，而在於**怎麼把數字變成一句不會誤導人的話**。
// 兩輪真機資料各推翻了一種算法：
//
// 1. **一次性暖機被攤成成長率。** 26 MB 起始、51 分 30 MB、55 分 30 MB、59 分 30 MB
//    ——早就持平了，但首末斜率報成「+4 MB/小時」，看起來像還在漲。
//    → 加上**近期斜率**（最後幾筆），排在整體前面。
// 2. **狀態切換被攤成成長率。** 閒置 30 MB → 按下「開始觀察」→ 130 MB，
//    首末斜率報成「+144 MB/小時」。但那不是速率，那是一個**階段落差**：
//    閒置與觀察中是兩個不同的工作集，把它們接成一條線去取斜率沒有意義。
//    → 斜率**不跨越狀態邊界**（`regime`），見 `currentRegimeSamples`。
//
// 兩次的共同教訓：**一個看起來像資料的猜測，比「不知道」更糟**——它會讓人停止繼續查，
// 或往錯的方向查。所以這裡寧可少報一個數字，也不報一個需要附帶說明才不會被誤解的數字。
//
// 這裡只放**純值**：環狀緩衝、分段、斜率、判讀文字。真正去問系統要數字的那一步
// 在 app 端（🔒），因為那是 mach 呼叫。

/// 一次取樣：時間 + 實體足跡（MB）+ 當時處於哪個狀態。
public struct MemorySample: Sendable, Equatable {
    public let at: Date
    public let footprintMB: Double
    /// 取樣當下的狀態（"閒置" / "觀察中" / "接手中"）。**斜率不跨越它。**
    public let regime: String

    public init(at: Date, footprintMB: Double, regime: String = "") {
        self.at = at
        self.footprintMB = footprintMB
        self.regime = regime
    }
}

/// 取樣紀錄。容量有上限——一個為了查記憶體而無上限成長的緩衝會很難堪。
public struct MemorySampleLog: Sendable {
    public private(set) var samples: [MemorySample] = []
    public let capacity: Int
    /// 同狀態下兩筆取樣的最小間隔。
    ///
    /// 存在的理由：狀態切換時前後各取一次，而切換路徑可能疊在一起
    /// （`toggleObserving` 內部又呼叫 `stopAll`），同一個瞬間會冒出兩三筆一模一樣的點。
    /// 那些點不帶任何資訊，只會讓「幾個樣本」這個數字騙人。
    public let minimumInterval: TimeInterval

    public init(capacity: Int = 200, minimumInterval: TimeInterval = 1) {
        self.capacity = max(2, capacity)
        self.minimumInterval = minimumInterval
    }

    /// 記錄一筆。同狀態且間隔過短時**丟棄**，回傳是否真的記下來了。
    @discardableResult
    public mutating func record(_ sample: MemorySample) -> Bool {
        if let last = samples.last, last.regime == sample.regime,
           sample.at.timeIntervalSince(last.at) < minimumInterval {
            return false
        }
        samples.append(sample)
        if samples.count > capacity { samples.removeFirst(samples.count - capacity) }
        return true
    }

    public var first: MemorySample? { samples.first }
    public var latest: MemorySample? { samples.last }
    /// 有史以來的峰值（跨所有狀態）。
    public var allTimePeakMB: Double? { samples.map(\.footprintMB).max() }

    /// **目前這個狀態**的所有取樣。斜率與峰值都只看這一段。
    ///
    /// 閒置與觀察中的工作集差了一個數量級，把兩段接成一條線去取斜率，
    /// 得到的是「階段落差 ÷ 總時間」——一個沒有物理意義、但看起來很像成長率的數字。
    public var currentRegimeSamples: [MemorySample] { currentRegime }

    /// 本階段峰值。用本階段而不是全期：判斷「觀察中會不會漏」時，
    /// 上一個階段的峰值只是雜訊。全期峰值另外由 `allTimePeakMB` 提供。
    public var peakMB: Double? { currentRegime.map(\.footprintMB).max() }

    /// 本階段整體斜率（本階段第一筆 → 最後一筆），MB/小時。
    public var growthMBPerHour: Double? { slope(over: currentRegime) }

    /// 近期斜率（本階段最後 `window` 筆），MB/小時。
    ///
    /// 為什麼需要它：一次性暖機會被整體斜率攤成假的成長率——真機第一輪就是這樣，
    /// 明明 51→59 分鐘完全沒動，整體卻報 +4 MB/小時。近期斜率取最後幾筆，
    /// 既避開單點雜訊，也不會被階段開頭的暖機汙染。
    public func recentGrowthMBPerHour(window: Int = 3) -> Double? {
        slope(over: currentRegime.suffix(max(2, window)))
    }

    /// 近期是否可視為持平。門檻 1 MB/小時：低於這個值，一天也不到 25 MB，
    /// 而量測本身的雜訊（快取、字型、GC 時機）就有這個量級。
    public static let flatThresholdMBPerHour: Double = 1.0

    /// 選單上那一行。
    ///
    /// **狀態標在最前面、近期斜率排在整體前面**——要判斷「有沒有在漏」看的是這兩個。
    /// 樣本數與時間跨度一定要印：「+300 MB/小時」在只有兩個樣本、間隔 90 秒時完全
    /// 不能拿來下結論，而少了這兩個數字，讀的人沒有辦法知道這件事。
    public var summary: String {
        let segment = currentRegime
        guard let head = segment.first, let tail = segment.last else { return "記憶體：尚無取樣" }
        let spanMinutes = tail.at.timeIntervalSince(head.at) / 60
        let label = tail.regime.isEmpty ? "" : "〔\(tail.regime)〕"

        var line = String(format: "記憶體%@：%.0f MB（本階段起始 %.0f", label, tail.footprintMB, head.footprintMB)
        if let peakMB { line += String(format: "・峰值 %.0f", peakMB) }
        line += " MB）"

        if let recent = recentGrowthMBPerHour() {
            let verdict = abs(recent) < Self.flatThresholdMBPerHour ? "近期持平" : "近期"
            line += String(format: "・%@ %+.0f MB/小時", verdict, recent)
        } else {
            line += "・近期斜率待累積"
        }
        if let overall = growthMBPerHour {
            line += String(format: "・本階段 %+.0f MB/小時", overall)
        }
        return line + String(format: "（%d 樣本／%.0f 分）", segment.count, spanMinutes)
    }

    // MARK: - 階段軌跡

    /// 一個完整的狀態區段。
    public struct RegimeSegment: Sendable, Equatable {
        public let regime: String
        public let startMB: Double
        public let endMB: Double
        public let peakMB: Double
        public let minutes: Double
    }

    /// 依狀態切成一段一段（舊→新）。
    public var segments: [RegimeSegment] {
        var result: [RegimeSegment] = []
        var current: [MemorySample] = []
        func flush() {
            guard let head = current.first, let tail = current.last else { return }
            result.append(RegimeSegment(
                regime: head.regime,
                startMB: head.footprintMB,
                endMB: tail.footprintMB,
                peakMB: current.map(\.footprintMB).max() ?? head.footprintMB,
                minutes: tail.at.timeIntervalSince(head.at) / 60))
            current = []
        }
        for sample in samples {
            if let last = current.last, last.regime != sample.regime { flush() }
            current.append(sample)
        }
        flush()
        return result
    }

    /// 階段軌跡：`閒置 26→30・觀察中 30→130（峰 162）・閒置 130→92`
    ///
    /// 存在的理由是一個**只有跨階段才看得到的問題**：停止觀察後記憶體掉了，
    /// 但沒掉回原本的底線。那有兩種可能——留著不放的快取（無害，例如載入後就
    /// 不卸載的本地模型），或每跑一輪就往上疊一層（真的漏）。
    /// 兩者的差別只在「閒置的底線會不會一輪比一輪高」，而那要把好幾段並排才看得出來。
    /// 摘要那一行只講當下這一段，看不到這件事。
    public func regimeTrail(limit: Int = 4) -> String {
        let recent = segments.suffix(max(1, limit))
        guard !recent.isEmpty else { return "階段：尚無取樣" }
        let parts = recent.map { segment -> String in
            var text = segment.regime.isEmpty ? "?" : segment.regime
            text += String(format: " %.0f→%.0f", segment.startMB, segment.endMB)
            // 峰值只在它真的高過頭尾時才印——否則是重複資訊，把行擠長而已。
            if segment.peakMB > max(segment.startMB, segment.endMB) + 1 {
                text += String(format: "（峰 %.0f）", segment.peakMB)
            }
            return text
        }
        return "階段：" + parts.joined(separator: "・") + " MB"
    }

    /// 由後往前取到狀態改變為止。
    private var currentRegime: [MemorySample] {
        guard let current = samples.last?.regime else { return [] }
        var segment: [MemorySample] = []
        for sample in samples.reversed() {
            guard sample.regime == current else { break }
            segment.append(sample)
        }
        return segment.reversed()
    }

    private func slope<S: Sequence>(over window: S) -> Double? where S.Element == MemorySample {
        let points = Array(window)
        guard let head = points.first, let tail = points.last else { return nil }
        let seconds = tail.at.timeIntervalSince(head.at)
        guard seconds >= 60 else { return nil }        // 不足一分鐘的斜率沒有意義
        return (tail.footprintMB - head.footprintMB) / seconds * 3600
    }
}
