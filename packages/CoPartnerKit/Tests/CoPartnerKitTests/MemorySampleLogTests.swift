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
            l.record(MemorySample(at: t0.addingTimeInterval(p.minutes * 60), footprintMB: p.mb))
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
        XCTAssertTrue(s.contains("2 個樣本"), s)
        XCTAssertTrue(s.contains("60 分鐘"), s)
        XCTAssertTrue(s.contains("+60 MB/小時"), s)
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
}
