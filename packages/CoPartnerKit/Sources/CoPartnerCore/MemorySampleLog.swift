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

    /// 每小時成長多少 MB。
    ///
    /// 用**第一筆到最後一筆**的整體斜率，不是相鄰兩筆的差：取樣間隔不規則，
    /// 相鄰差會被「剛好連按兩次選單」這種零間隔放大成荒謬的數字。
    /// 樣本不足或時間跨度過短時回 nil——**寧可不報，也不要報一個看起來像資料的猜測**。
    public var growthMBPerHour: Double? {
        guard let first, let latest else { return nil }
        let seconds = latest.at.timeIntervalSince(first.at)
        guard seconds >= 60 else { return nil }        // 不足一分鐘的斜率沒有意義
        return (latest.footprintMB - first.footprintMB) / seconds * 3600
    }

    /// 選單上那一行。刻意把**樣本數與時間跨度**一起印出來——
    /// 「成長 300 MB/小時」在只有兩個樣本、間隔 90 秒時完全不能拿來下結論，
    /// 而少了這兩個數字，讀的人沒有辦法知道這件事。
    public var summary: String {
        guard let first, let latest else { return "記憶體：尚無取樣" }
        let spanMinutes = latest.at.timeIntervalSince(first.at) / 60
        var line = String(format: "記憶體：目前 %.0f MB・起始 %.0f MB", latest.footprintMB, first.footprintMB)
        if let peakMB { line += String(format: "・峰值 %.0f MB", peakMB) }
        if let rate = growthMBPerHour {
            line += String(format: "・成長 %+.0f MB/小時", rate)
        } else {
            line += "・成長率待累積"
        }
        return line + String(format: "（%d 個樣本／%.0f 分鐘）", samples.count, spanMinutes)
    }
}
