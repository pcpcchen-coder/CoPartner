import XCTest
import CoPartnerCore

/// 記憶體取樣紀錄（診斷工具）。
///
/// 這個型別本身沒有安全性，但它會被拿來**下判斷**——「有沒有洩漏」「修好了沒」。
/// 所以要守的性質是：**沒有把握的時候不要報數字**。一個看起來像資料的猜測
/// 比「不知道」更糟，因為它會讓人停止繼續查。
final class MemorySampleLogTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func log(_ points: [(minutes: Double, mb: Double)],
                     capacity: Int = 200) -> MemorySampleLog {
        var l = MemorySampleLog(capacity: capacity)
        for p in points {
            l.record(MemorySample(at: t0.addingTimeInterval(p.minutes * 60),
                                  footprintMB: p.mb, regime: "閒置"))
        }
        return l
    }

    /// 帶狀態的版本：`(分鐘, MB, 狀態)`。
    private func log(_ points: [(minutes: Double, mb: Double, regime: String)]) -> MemorySampleLog {
        var l = MemorySampleLog()
        for p in points {
            l.record(MemorySample(at: t0.addingTimeInterval(p.minutes * 60),
                                  footprintMB: p.mb, regime: p.regime))
        }
        return l
    }

    func testEmptyLogSaysSoInsteadOfShowingZeros() {
        XCTAssertEqual(MemorySampleLog().summary, "記憶體：尚無取樣")
        XCTAssertNil(MemorySampleLog().growthMBPerHour)
    }

    /// 一小時漲 60 MB → 60 MB/小時。
    func testGrowthRateIsPerHour() {
        let rate = log([(0, 100), (60, 160)]).growthMBPerHour
        XCTAssertEqual(try XCTUnwrap(rate), 60, accuracy: 0.001)
    }

    /// 斜率取**首末兩點**，不是相鄰差。取樣間隔不規則，相鄰差會被
    /// 「剛好連按兩次選單」這種近乎零的間隔放大成荒謬的數字。
    func testRateUsesOverallSlopeNotLastGap() {
        // 兩小時漲 120 MB（＝60 MB/小時），但最後兩筆間隔 6 秒漲了 1 MB
        // ——若用相鄰差會算出 600 MB/小時。
        let rate = log([(0, 100), (119.9, 219), (120, 220)]).growthMBPerHour
        XCTAssertEqual(try XCTUnwrap(rate), 60, accuracy: 0.5)
    }

    /// 時間跨度太短就**不報**——寧可說「待累積」也不要給一個不能用的斜率。
    func testTooShortSpanReportsNothing() {
        XCTAssertNil(log([(0, 100), (0.5, 200)]).growthMBPerHour)
        XCTAssertTrue(log([(0, 100), (0.5, 200)]).summary.contains("待累積"))
    }

    /// 摘要必須帶樣本數與時間跨度：沒有這兩個數字，讀的人無法判斷該不該相信那個斜率。
    func testSummaryCarriesSampleCountAndSpan() {
        let s = log([(0, 100), (60, 160)]).summary
        XCTAssertTrue(s.contains("2 樣本"), s)
        XCTAssertTrue(s.contains("60 分"), s)
        XCTAssertTrue(s.contains("+60 MB/小時"), s)
    }

    // MARK: - 近期斜率（真機第一輪資料逼出來的）

    /// **真機序列重演。** 26 MB 起始、51 分 30 MB、55 分 30 MB、59 分 30 MB
    /// ——啟動暖機漲了 4 MB 然後完全持平。整體斜率會把那 4 MB 攤成「+4 MB/小時」，
    /// 看起來像還在漲；近期斜率必須看得出它早就停了。
    func testWarmUpThenFlatIsNotReportedAsGrowth() {
        let l = log([(0, 26), (51, 30), (55, 30), (59, 30)])
        XCTAssertEqual(try XCTUnwrap(l.growthMBPerHour), 4, accuracy: 0.5,
                       "整體斜率確實是 +4——這正是誤導的來源")
        XCTAssertEqual(try XCTUnwrap(l.recentGrowthMBPerHour()), 0, accuracy: 0.001,
                       "近期完全持平")
        XCTAssertTrue(l.summary.contains("近期持平"), l.summary)
    }

    /// 反面：真的持續在漲時，近期斜率不可以被判成持平。
    func testSustainedGrowthIsNotCalledFlat() {
        let l = log([(0, 100), (20, 140), (40, 180), (60, 220)])
        XCTAssertEqual(try XCTUnwrap(l.recentGrowthMBPerHour()), 120, accuracy: 1)
        XCTAssertFalse(l.summary.contains("近期持平"), l.summary)
    }

    /// 近期視窗只看最後幾筆——開頭的暖機不可以汙染它。
    func testRecentWindowIgnoresEarlySamples() {
        let l = log([(0, 26), (1, 500), (30, 30), (60, 30)])
        XCTAssertEqual(try XCTUnwrap(l.recentGrowthMBPerHour(window: 2)), 0, accuracy: 0.001)
    }

    /// 視窗內跨度不足一分鐘 → 不報（與整體斜率同一條規則）。
    func testRecentSlopeNeedsEnoughSpan() {
        let l = log([(0, 100), (59.5, 200), (59.7, 201), (59.9, 202)])
        XCTAssertNil(l.recentGrowthMBPerHour(), "最後三筆只跨 24 秒，不該報")
        XCTAssertTrue(l.summary.contains("近期斜率待累積"), l.summary)
        XCTAssertNotNil(l.growthMBPerHour, "整體跨度夠，仍要報")
    }

    /// 視窗至少 2 筆——傳 0 或 1 不可以讓近期斜率永遠是 nil。
    func testRecentWindowHasAFloor() {
        let l = log([(0, 100), (60, 160)])
        XCTAssertEqual(try XCTUnwrap(l.recentGrowthMBPerHour(window: 1)), 60, accuracy: 0.001)
    }

    /// 下降也要看得見（修好之後要能確認）。
    func testShrinkingIsReportedAsNegative() {
        let rate = log([(0, 300), (60, 240)]).growthMBPerHour
        XCTAssertEqual(try XCTUnwrap(rate), -60, accuracy: 0.001)
        XCTAssertTrue(log([(0, 300), (60, 240)]).summary.contains("-60 MB/小時"))
    }

    /// 峰值不可被之後的下降蓋掉——告警是在峰值那一刻跳的。
    func testPeakSurvivesLaterDrop() {
        XCTAssertEqual(log([(0, 100), (30, 900), (60, 200)]).peakMB, 900)
    }

    /// **一個為了查記憶體而無上限成長的緩衝會很難堪。**
    func testCapacityIsEnforcedAndOldestDropFirst() {
        let l = log((0..<50).map { (Double($0), Double(100 + $0)) }, capacity: 10)
        XCTAssertEqual(l.samples.count, 10)
        XCTAssertEqual(l.latest?.footprintMB, 149)
        XCTAssertEqual(l.first?.footprintMB, 140, "應該丟掉最舊的，留最新的 10 筆")
    }

    /// 容量至少要能算斜率——傳 0 或 1 不可以讓 `growthMBPerHour` 永遠是 nil。
    func testCapacityHasAFloor() {
        var l = MemorySampleLog(capacity: 0)
        l.record(MemorySample(at: t0, footprintMB: 100))
        l.record(MemorySample(at: t0.addingTimeInterval(3600), footprintMB: 160))
        XCTAssertEqual(l.samples.count, 2)
        XCTAssertEqual(try XCTUnwrap(l.growthMBPerHour), 60, accuracy: 0.001)
    }

    // MARK: - 狀態分段（真機第二輪資料逼出來的）

    /// **真機序列重演。** 閒置 43 分鐘停在 30 MB，按下「開始觀察」之後衝到 162 MB，
    /// 再回落到 130 MB。首末斜率會報成「+144 MB/小時」——但那不是速率，
    /// 那是一個**階段落差**：閒置與觀察中是兩個不同的工作集。
    func testSlopeDoesNotCrossRegimeBoundary() throws {
        let l = log([(0, 26, "閒置"), (30, 30, "閒置"), (43, 30, "閒置"),
                     (43, 30, "觀察中"), (60, 162, "觀察中"), (86, 130, "觀察中")])
        // 觀察中這一段是 30 → 130 MB／43 分鐘 ≈ +140 MB/小時。
        // 若跨越邊界，(0,26) → (86,130) 只會算出約 +73——一個誰都解讀不了的數字。
        XCTAssertEqual(try XCTUnwrap(l.growthMBPerHour), 100 / (43.0 / 60), accuracy: 5,
                       "本階段斜率只能從觀察中的第一筆算起")
        XCTAssertTrue(l.summary.contains("觀察中"), l.summary)
        XCTAssertFalse(l.summary.contains("起始 26"), "26 MB 是上一個階段的事：\(l.summary)")
    }

    /// 上去又下來 ≠ 無上限成長。近期斜率必須看得出它在回收。
    func testPeakThenReclaimShowsNegativeRecentSlope() throws {
        let l = log([(43, 30, "觀察中"), (60, 162, "觀察中"), (86, 130, "觀察中")])
        XCTAssertLessThan(try XCTUnwrap(l.recentGrowthMBPerHour(window: 2)), 0,
                          "162 → 130 是在回收，不是在漲")
        XCTAssertEqual(l.peakMB, 162)
    }

    /// 本階段峰值不可被上一個階段的峰值汙染。
    func testPeakIsPerRegimeButAllTimePeakSurvives() {
        let l = log([(0, 500, "觀察中"), (10, 500, "觀察中"),
                     (10, 40, "閒置"), (70, 42, "閒置")])
        XCTAssertEqual(l.peakMB, 42, "本階段（閒置）的峰值")
        XCTAssertEqual(l.allTimePeakMB, 500, "全期峰值仍查得到")
    }

    /// 切回原本的狀態算**新的一段**——中間隔了另一個狀態，工作集早就不同了。
    func testReturningToAPreviousRegimeStartsAFreshSegment() {
        let l = log([(0, 26, "閒置"), (30, 30, "閒置"),
                     (30, 30, "觀察中"), (60, 160, "觀察中"),
                     (60, 60, "閒置"), (120, 62, "閒置")])
        XCTAssertEqual(l.currentRegimeSamples.count, 2)
        XCTAssertEqual(l.currentRegimeSamples.first?.footprintMB, 60)
    }

    // MARK: - 去重

    /// 狀態切換前後各取一次，而切換路徑可能疊在一起（`toggleObserving` 內部又呼叫
    /// `stopAll`），同一個瞬間會冒出好幾筆一模一樣的點。它們不帶資訊，
    /// 只會讓「幾個樣本」這個數字騙人。
    func testSameInstantSameRegimeIsDeduplicated() {
        var l = MemorySampleLog()
        XCTAssertTrue(l.record(MemorySample(at: t0, footprintMB: 30, regime: "閒置")))
        XCTAssertFalse(l.record(MemorySample(at: t0, footprintMB: 30, regime: "閒置")))
        XCTAssertFalse(l.record(MemorySample(at: t0.addingTimeInterval(0.5),
                                             footprintMB: 31, regime: "閒置")))
        XCTAssertEqual(l.samples.count, 1)
    }

    /// 但**狀態不同就一定要留**——那正是階段邊界，丟掉它新階段就沒有起點了。
    func testRegimeChangeAtSameInstantIsKept() {
        var l = MemorySampleLog()
        XCTAssertTrue(l.record(MemorySample(at: t0, footprintMB: 30, regime: "閒置")))
        XCTAssertTrue(l.record(MemorySample(at: t0, footprintMB: 30, regime: "觀察中")))
        XCTAssertEqual(l.samples.count, 2)
    }

    // MARK: - 階段軌跡（真機第三輪逼出來的）

    /// **真機序列重演。** 閒置 26→30，觀察中衝到 162 再回落到 130，
    /// 停止觀察後掉到 92——但沒回到 30。軌跡要讓這三段並排看得到。
    func testTrailShowsEachSegmentStartEndAndPeak() {
        let l = log([(0, 26, "閒置"), (43, 30, "閒置"),
                     (43, 30, "觀察中"), (60, 162, "觀察中"), (86, 130, "觀察中"),
                     (86, 130, "閒置"), (90, 92, "閒置")])
        let trail = l.regimeTrail()
        XCTAssertTrue(trail.contains("閒置 26→30"), trail)
        XCTAssertTrue(trail.contains("觀察中 30→130（峰 162）"), trail)
        XCTAssertTrue(trail.contains("閒置 130→92"), trail)
    }

    /// 峰值只在真的高過頭尾時才印——否則是重複資訊，把行擠長而已。
    func testTrailOmitsPeakWhenItEqualsTheEndpoints() {
        let trail = log([(0, 26, "閒置"), (43, 30, "閒置")]).regimeTrail()
        XCTAssertEqual(trail, "階段：閒置 26→30 MB")
    }

    /// **這才是重點：閒置的底線有沒有一輪比一輪高。**
    /// 疊高 ＝ 真的在漏；穩定 ＝ 留著不放的快取（例如載入後不卸載的本地模型）。
    func testTrailMakesARatchetingIdleBaselineVisible() {
        let l = log([(0, 30, "閒置"),
                     (0, 30, "觀察中"), (20, 160, "觀察中"),
                     (20, 92, "閒置"), (30, 92, "閒置"),
                     (30, 92, "觀察中"), (50, 220, "觀察中"),
                     (50, 150, "閒置"), (60, 150, "閒置")])
        let trail = l.regimeTrail()
        XCTAssertTrue(trail.contains("閒置 92→92"), trail)
        XCTAssertTrue(trail.contains("閒置 150→150"), trail)   // 92 → 150：底線疊高了
    }

    /// 只留最近幾段——十輪之後那一行不能長到看不完。
    func testTrailIsLimited() {
        var points: [(minutes: Double, mb: Double, regime: String)] = []
        for i in 0..<10 {
            points.append((Double(i * 10), 30, "閒置"))
            points.append((Double(i * 10) + 5, 100, "觀察中"))
        }
        let trail = log(points).regimeTrail(limit: 3)
        XCTAssertEqual(trail.components(separatedBy: "・").count, 3, trail)
    }

    func testEmptyTrailSaysSo() {
        XCTAssertEqual(MemorySampleLog().regimeTrail(), "階段：尚無取樣")
    }
}
