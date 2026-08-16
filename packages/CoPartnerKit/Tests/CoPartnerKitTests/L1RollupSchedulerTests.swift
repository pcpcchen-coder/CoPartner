import XCTest
import ScriptNarrator

/// L1 rollup 排程（step 42）：何時該叫模型。時鐘由外部注入 → 完全確定性。
///
/// 重點在**新活動偵測**：`EventLog` 會就地修改最後一行（打字合併 / scroll 聚合），
/// `EventLogFeed` 又是 ring buffer（飽和後行數不再成長）。這兩件事各自都足以讓
/// 「行數差」永久歸零、rollup 再也不觸發，所以下面兩個 regression 測試釘住它們。
final class L1RollupSchedulerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func t(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    // MARK: - 新活動偵測

    func testAppendedLineCountsAsActivity() {
        var s = L1RollupScheduler()
        XCTAssertTrue(s.observe(snapshot: ["a"], at: t0))
        XCTAssertTrue(s.observe(snapshot: ["a", "b"], at: t(1)))
        XCTAssertEqual(s.pendingCredits, 2)
    }

    func testIdenticalSnapshotIsNotActivity() {
        var s = L1RollupScheduler()
        s.observe(snapshot: ["a", "b"], at: t0)
        XCTAssertFalse(s.observe(snapshot: ["a", "b"], at: t(1)))
        XCTAssertEqual(s.pendingCredits, 1)   // 沒有多算
    }

    /// regression：同欄位連續打字會**就地改寫最後一行**，行數完全不動。
    /// 若用行數差當 delta，使用者打一整段字都不會觸發任何敘事。
    func testInPlaceTailMutationCountsAsActivity() {
        var s = L1RollupScheduler()
        s.observe(snapshot: ["[t] TYPE field=x text=\"h\""], at: t0)
        let grew = s.observe(snapshot: ["[t] TYPE field=x text=\"he\""], at: t(1))
        XCTAssertTrue(grew, "行數沒變但末行內容變了，必須算成新活動")
        XCTAssertEqual(s.pendingCredits, 2)
    }

    /// regression：ring buffer 飽和後行數固定在 capacity，舊行從頭被丟掉。
    /// 若用行數差當 delta，長時間觀察後 rollup 會永久停擺。
    func testRingBufferSaturationStillCountsAsActivity() {
        var s = L1RollupScheduler()
        let saturated = (1...300).map { "line\($0)" }
        s.observe(snapshot: saturated, at: t0)
        let shifted = Array(saturated.dropFirst()) + ["line301"]   // 行數一樣是 300
        XCTAssertEqual(shifted.count, saturated.count)
        XCTAssertTrue(s.observe(snapshot: shifted, at: t(1)), "行數相同但內容前移，仍是新活動")
    }

    func testEmptySnapshotIsNotActivity() {
        var s = L1RollupScheduler()
        XCTAssertFalse(s.observe(snapshot: [], at: t0))
        XCTAssertEqual(s.pendingCredits, 0)
    }

    // MARK: - 觸發條件

    func testNoActivityNeverTriggers() {
        var s = L1RollupScheduler()
        XCTAssertNil(s.evaluate(now: t(999), appChanged: false))
        XCTAssertNil(s.evaluate(now: t(999), appChanged: true))   // 連 app 換了也不觸發：沒東西可講
    }

    func testLineCountTrigger() {
        var s = L1RollupScheduler(minNewLines: 3, maxInterval: 999)
        s.observe(snapshot: ["a"], at: t0)
        s.observe(snapshot: ["a", "b"], at: t0)
        XCTAssertNil(s.evaluate(now: t(1), appChanged: false))    // 才 2 筆，未達門檻
        s.observe(snapshot: ["a", "b", "c"], at: t0)
        XCTAssertEqual(s.evaluate(now: t(1), appChanged: false), .lineCount)
    }

    func testIntervalTriggerFiresForSlowActivity() {
        var s = L1RollupScheduler(minNewLines: 100, maxInterval: 20)
        s.observe(snapshot: ["a"], at: t0)
        XCTAssertNil(s.evaluate(now: t(19), appChanged: false))
        XCTAssertEqual(s.evaluate(now: t(20), appChanged: false), .interval,
                       "慢速操作永遠達不到行數門檻，時間到就必須出一個 step")
    }

    func testAppBoundaryTriggersImmediately() {
        var s = L1RollupScheduler(minNewLines: 100, maxInterval: 999)
        s.observe(snapshot: ["a"], at: t0)
        XCTAssertEqual(s.evaluate(now: t(1), appChanged: true), .appBoundary)
    }

    func testAppBoundaryOutranksLineCount() {
        var s = L1RollupScheduler(minNewLines: 1, maxInterval: 999)
        s.observe(snapshot: ["a"], at: t0)
        XCTAssertEqual(s.evaluate(now: t(1), appChanged: true), .appBoundary)
    }

    // MARK: - in-flight 互斥

    func testNoOverlappingRollups() {
        var s = L1RollupScheduler(minNewLines: 1, maxInterval: 999)
        s.observe(snapshot: ["a"], at: t0)
        XCTAssertEqual(s.evaluate(now: t(1), appChanged: false), .lineCount)
        XCTAssertTrue(s.isRollupInFlight)
        s.observe(snapshot: ["a", "b"], at: t(2))
        XCTAssertNil(s.evaluate(now: t(3), appChanged: true),
                     "上一輪還沒回來就不該再發動：模型呼叫要數百 ms，重疊會浪費算力且讓結果亂序")
    }

    func testCompleteClearsCreditsAndAllowsNextRollup() {
        var s = L1RollupScheduler(minNewLines: 1, maxInterval: 999)
        s.observe(snapshot: ["a"], at: t0)
        _ = s.evaluate(now: t(1), appChanged: false)
        s.complete()
        XCTAssertFalse(s.isRollupInFlight)
        XCTAssertEqual(s.pendingCredits, 0)
        XCTAssertNil(s.evaluate(now: t(2), appChanged: false), "清空後沒有新活動就不該再捲")
        s.observe(snapshot: ["a", "b"], at: t(3))
        XCTAssertEqual(s.evaluate(now: t(4), appChanged: false), .lineCount)
    }

    /// interval 的計時基準必須在 complete 後重置，否則第二輪會一觸發就立刻又到期。
    func testIntervalClockResetsAfterComplete() {
        var s = L1RollupScheduler(minNewLines: 100, maxInterval: 20)
        s.observe(snapshot: ["a"], at: t0)
        XCTAssertEqual(s.evaluate(now: t(20), appChanged: false), .interval)
        s.complete()
        s.observe(snapshot: ["a", "b"], at: t(21))
        XCTAssertNil(s.evaluate(now: t(30), appChanged: false), "新一批的 20s 應從 t=21 起算")
        XCTAssertEqual(s.evaluate(now: t(41), appChanged: false), .interval)
    }

    // MARK: - 視窗

    func testWindowTakesMostRecentLines() {
        let s = L1RollupScheduler(windowLines: 3)
        XCTAssertEqual(s.window(of: ["a", "b", "c", "d", "e"]), ["c", "d", "e"])
    }

    func testWindowShorterThanLimitReturnsAll() {
        let s = L1RollupScheduler(windowLines: 40)
        XCTAssertEqual(s.window(of: ["a", "b"]), ["a", "b"])
    }

    func testDegenerateConfigIsClamped() {
        let s = L1RollupScheduler(minNewLines: 0, maxInterval: -5, windowLines: 0)
        XCTAssertEqual(s.windowLines, 1)
        XCTAssertEqual(s.minNewLines, 1)
        XCTAssertEqual(s.maxInterval, 0)
    }
}
