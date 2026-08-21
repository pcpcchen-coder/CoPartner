import Foundation
// 診斷工具（step 53.7 / handoff §7.6.6）：記憶體用量的成長曲線。
//
// 起因：真機上**沒有按「開始觀察」**、只是讓 app 開著，就會跳記憶體告警。
// 這句話一次砍掉原本兩個主要嫌疑（`CaptureEngine` 的無上限 `AsyncStream`、
// 每 3 秒的全螢幕截圖）——兩者都只在觀察開始後才存在。
//
// ## 為什麼是「開選單時取樣」而不是定時器
//
// 我們要量的正是**閒置路徑**。在閒置路徑上裝一個每 N 秒醒來的定時器，
// 等於在被觀察的對象裡加一個新的觀察者：它自己會配置、會讓 runloop 醒來、
// 會改變我們想量的那條曲線。
//
// 改成「每次打開選單時取一個樣」：背景成本**恰好是零**，而使用者本來就會不時
// 打開選單看一眼，那些時間點自然就串成一條曲線。代價是取樣間隔不規則——
// 所以成長率一律以「每小時多少 MB」報，而不是「每次多少 MB」。
//
// 這裡只放**純值**：環狀緩衝、成長率、判讀文字。真正去問系統要數字的那一步
// 在 app 端（🔒），因為那是 mach 呼叫。

/// 一次取樣：時間 + 實體足跡（MB）。
public struct MemorySample: Sendable, Equatable {
    public let at: Date
    public let footprintMB: Double
    public init(at: Date, footprintMB: Double) {
        self.at = at
        self.footprintMB = footprintMB
    }
}

/// 取樣紀錄。容量有上限——一個為了查記憶體而無上限成長的緩衝會很難堪。
public struct MemorySampleLog: Sendable {
    public private(set) var samples: [MemorySample] = []
    public let capacity: Int

    public init(capacity: Int = 200) { self.capacity = max(2, capacity) }

    public mutating func record(_ sample: MemorySample) {
        samples.append(sample)
        if samples.count > capacity { samples.removeFirst(samples.count - capacity) }
    }

    public var first: MemorySample? { samples.first }
    public var latest: MemorySample? { samples.last }
    public var peakMB: Double? { samples.map(\.footprintMB).max() }

    /// 每小時成長多少 MB（**整體**：第一筆到最後一筆）。
    ///
    /// 不用相鄰兩筆的差：取樣間隔不規則，相鄰差會被「剛好連按兩次選單」這種零間隔
    /// 放大成荒謬的數字。樣本不足或時間跨度過短時回 nil——
    /// **寧可不報，也不要報一個看起來像資料的猜測**。
    public var growthMBPerHour: Double? { slope(over: samples) }

    /// 每小時成長多少 MB（**近期**：最後 `window` 筆）。
    ///
    /// 為什麼需要這個：真機第一輪資料長這樣——
    /// 26 MB 起始，51 分鐘時 30 MB，55 分鐘 30 MB，59 分鐘 30 MB。
    /// 也就是**啟動暖機漲了 4 MB，然後完全持平**。但整體斜率把那 4 MB 攤到
    /// 一小時上，報成「+4 MB/小時」——看起來像還在漲，實際上早就停了。
    ///
    /// 整體斜率是為了避開相鄰差的雜訊而選的，結果換成另一種誤導：
    /// 它分不出「一次性暖機後持平」與「持續成長」，而那正是我們唯一想知道的事。
    /// 近期斜率取最後幾筆，既避開單點雜訊，也不會被開頭的暖機汙染。
    public func recentGrowthMBPerHour(window: Int = 3) -> Double? {
        slope(over: samples.suffix(max(2, window)))
    }

    /// 近期是否可視為持平。門檻 1 MB/小時：低於這個值，一天也不到 25 MB，
    /// 而量測本身的雜訊（GC 時機、字型快取）就有這個量級。
    public static let flatThresholdMBPerHour: Double = 1.0

    private func slope<S: Sequence>(over window: S) -> Double? where S.Element == MemorySample {
        let points = Array(window)
        guard let head = points.first, let tail = points.last else { return nil }
        let seconds = tail.at.timeIntervalSince(head.at)
        guard seconds >= 60 else { return nil }        // 不足一分鐘的斜率沒有意義
        return (tail.footprintMB - head.footprintMB) / seconds * 3600
    }

    /// 選單上那一行。
    ///
    /// **近期斜率排在整體前面**，因為要判斷「有沒有在漏」看的是它。
    /// 樣本數與時間跨度一定要印——「+300 MB/小時」在只有兩個樣本、間隔 90 秒時
    /// 完全不能拿來下結論，而少了這兩個數字，讀的人沒有辦法知道這件事。
    public var summary: String {
        guard let first, let latest else { return "記憶體：尚無取樣" }
        let spanMinutes = latest.at.timeIntervalSince(first.at) / 60
        var line = String(format: "記憶體：%.0f MB（起始 %.0f", latest.footprintMB, first.footprintMB)
        if let peakMB { line += String(format: "・峰值 %.0f", peakMB) }
        line += " MB）"
        if let recent = recentGrowthMBPerHour() {
            let verdict = abs(recent) < Self.flatThresholdMBPerHour ? "近期持平" : "近期"
            line += String(format: "・%@ %+.0f MB/小時", verdict, recent)
        } else {
            line += "・近期斜率待累積"
        }
        if let overall = growthMBPerHour {
            line += String(format: "・整體 %+.0f MB/小時", overall)
        }
        return line + String(format: "（%d 樣本／%.0f 分）", samples.count, spanMinutes)
    }
}
