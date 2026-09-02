import XCTest
import CoPartnerCore
import CaptureEngine

/// 擷取活動摘要（TileEvent → 選單顯示）。step 16 協調邏輯。
final class CaptureActivityTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)
    private func event(_ x: Int, _ y: Int) -> TileEvent {
        TileEvent(tileX: x, tileY: y, state: .warm, dhash: 0, timestamp: t0)
    }

    func testEmptyHasNoActivity() {
        let activity = CaptureActivity()
        XCTAssertEqual(activity.totalDirtyEvents, 0)
        XCTAssertNil(activity.lastTile)
        XCTAssertTrue(activity.summary.contains("尚無"))
    }

    func testRecordsCountAndLastTile() {
        var activity = CaptureActivity()
        activity.record(event(1, 2))
        activity.record(event(3, 4))
        XCTAssertEqual(activity.totalDirtyEvents, 2)
        XCTAssertEqual(activity.lastTile, TileXY(x: 3, y: 4))
    }

    func testSummaryReflectsLatest() {
        var activity = CaptureActivity()
        activity.record(event(5, 6))
        XCTAssertTrue(activity.summary.contains("1 次變動"), activity.summary)
        XCTAssertTrue(activity.summary.contains("(5,6)"), activity.summary)
    }

    // MARK: - 產生端 vs 消費端（step 53.7：串流改成有界之後）

    /// 沒有塞車時兩個數字一致，摘要不該多出「丟棄」字樣。
    func testNoDropsWhenConsumerKeepsUp() {
        var activity = CaptureActivity()
        activity.record(event(1, 1))
        activity.record(event(2, 2))
        activity.producedEvents = 2
        XCTAssertEqual(activity.droppedEvents, 0)
        XCTAssertFalse(activity.summary.contains("丟棄"), activity.summary)
        XCTAssertTrue(activity.summary.contains("2 次變動"), activity.summary)
    }

    /// **塞車必須看得見。** 串流有界之後，消費端跟不上時舊事件會被丟掉；
    /// 只記「收到幾個」的話，畫面上那個數字會在塞車時**靜默變小**——
    /// 而塞車正是這個數字最該說出來的時候（它就是記憶體診斷要找的訊號）。
    func testDropsAreReportedNotHidden() {
        var activity = CaptureActivity()
        activity.record(event(1, 1))
        activity.producedEvents = 1000
        XCTAssertEqual(activity.droppedEvents, 999)
        XCTAssertTrue(activity.summary.contains("1000 次變動"), activity.summary)
        XCTAssertTrue(activity.summary.contains("丟棄 999"), activity.summary)
    }

    /// 產生端計數還沒填（或填得比收到的少）時不可以算出負的丟棄數，
    /// 也不可以讓顯示的次數比實際收到的還少。
    func testProducedCountLaggingBehindIsClamped() {
        var activity = CaptureActivity()
        activity.record(event(1, 1))
        activity.record(event(2, 2))
        activity.producedEvents = 0              // 尚未填
        XCTAssertEqual(activity.droppedEvents, 0)
        XCTAssertTrue(activity.summary.contains("2 次變動"), activity.summary)
    }

    /// 兩邊都是 0 → 仍然是「尚無」，不能因為多了一個欄位就變成「0 次變動」。
    func testStillEmptyWhenNeitherCounted() {
        XCTAssertTrue(CaptureActivity().summary.contains("尚無"))
    }
}
