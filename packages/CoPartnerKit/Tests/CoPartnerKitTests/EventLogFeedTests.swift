import XCTest
import Foundation
import ScriptNarrator

/// 即時劇本 feed（v2.1 §3 ring buffer）。record / 容量上限 / 停止 / 快照串流。
final class EventLogFeedTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private func at(_ s: Double) -> Date { Date(timeIntervalSinceReferenceDate: s) }

    func testRecordProducesFormattedLine() async {
        let feed = EventLogFeed(capacity: 10, timeZone: utc)
        await feed.record(.focus(app: "Xcode", window: "A.swift"), at: at(0))
        let lines = await feed.lines
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].contains("FOCUS"), lines[0])
        XCTAssertTrue(lines[0].contains("app=Xcode"), lines[0])
    }

    func testRingBufferDropsOldestBeyondCapacity() async {
        let feed = EventLogFeed(capacity: 3, timeZone: utc)
        for i in 0..<5 {
            await feed.record(.switchApp(app: "App\(i)", window: "W"), at: at(Double(i)))
        }
        let lines = await feed.lines
        XCTAssertEqual(lines.count, 3)             // 上限 3
        XCTAssertTrue(lines[0].contains("App2"), lines[0])   // App0 / App1 已丟棄
        XCTAssertTrue(lines[2].contains("App4"), lines[2])
    }

    func testStopIgnoresFurtherRecords() async {
        let feed = EventLogFeed(capacity: 10, timeZone: utc)
        await feed.record(.focus(app: "A", window: "W"), at: at(0))
        await feed.stop()
        await feed.record(.focus(app: "B", window: "W"), at: at(1))
        let lines = await feed.lines
        XCTAssertEqual(lines.count, 1)             // 停止後不再新增
    }

    func testUpdatesStreamDeliversLatestSnapshot() async {
        let feed = EventLogFeed(capacity: 10, timeZone: utc)
        await feed.record(.focus(app: "A", window: "W"), at: at(0))
        var iterator = feed.updates.makeAsyncIterator()
        let snapshot = await iterator.next()
        XCTAssertEqual(snapshot?.count, 1)         // 訂閱讀到最新快照
    }
}
