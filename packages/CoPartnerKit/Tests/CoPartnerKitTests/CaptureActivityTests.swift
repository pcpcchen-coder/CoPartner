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
}
