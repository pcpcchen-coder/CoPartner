import XCTest
import Foundation
import ScriptNarrator

/// L0 合併 / 節流規則（v2.1 §2）。注入 now: 讓時間窗判斷決定性。
final class EventLogMergeTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private func at(_ s: Double) -> Date { Date(timeIntervalSinceReferenceDate: s) }

    private func makeLog() -> EventLog {
        var log = EventLog()
        log.timeZone = utc
        return log
    }

    func testConsecutiveTypingSameFieldMergesIntoOneLine() {
        var log = makeLog()
        log.record(.type(field: "AXTextArea", text: "func "), at: at(0))
        log.record(.type(field: "AXTextArea", text: "reconnect"), at: at(1))   // 2s 內
        XCTAssertEqual(log.lines.count, 1)
        XCTAssertTrue(log.lines[0].contains("text=\"func reconnect\""), log.lines[0])
    }

    func testRollingWindowMergesAcrossMultipleKeystrokes() {
        var log = makeLog()
        log.record(.type(field: "AXTextArea", text: "a"), at: at(0))
        log.record(.type(field: "AXTextArea", text: "b"), at: at(1.5))   // 距前 1.5s
        log.record(.type(field: "AXTextArea", text: "c"), at: at(3.0))   // 距前 1.5s（滾動窗）
        XCTAssertEqual(log.lines.count, 1)
        XCTAssertTrue(log.lines[0].contains("text=\"abc\""), log.lines[0])
    }

    func testTypingDifferentFieldDoesNotMerge() {
        var log = makeLog()
        log.record(.type(field: "AXTextArea", text: "a"), at: at(0))
        log.record(.type(field: "AXTextField", text: "b"), at: at(0.5))
        XCTAssertEqual(log.lines.count, 2)
    }

    func testTypingBeyondWindowStartsNewLine() {
        var log = makeLog()
        log.record(.type(field: "AXTextArea", text: "a"), at: at(0))
        log.record(.type(field: "AXTextArea", text: "b"), at: at(3))   // 距前 3s > 2s
        XCTAssertEqual(log.lines.count, 2)
    }

    func testMergedLineKeepsStartTimestamp() {
        var log = makeLog()
        log.record(.type(field: "AXTextArea", text: "a"), at: at(0))   // 參考日 00:00:00.000 UTC
        log.record(.type(field: "AXTextArea", text: "b"), at: at(1))
        XCTAssertEqual(log.lines.count, 1)
        XCTAssertTrue(log.lines[0].hasPrefix("[00:00:00.000]"), log.lines[0])  // 沿用起始時間
    }

    func testScrollSameDirectionAggregatesDistance() {
        var log = makeLog()
        log.record(.scroll(app: "Safari", direction: .down, distance: 100), at: at(0))
        log.record(.scroll(app: "Safari", direction: .down, distance: 40), at: at(0.5))  // 1s 內
        XCTAssertEqual(log.lines.count, 1)
        XCTAssertTrue(log.lines[0].contains("dist=140"), log.lines[0])
    }

    func testScrollOppositeDirectionDoesNotMerge() {
        var log = makeLog()
        log.record(.scroll(app: "Safari", direction: .down, distance: 100), at: at(0))
        log.record(.scroll(app: "Safari", direction: .up, distance: 40), at: at(0.5))
        XCTAssertEqual(log.lines.count, 2)
    }

    func testScrollBeyondWindowStartsNewLine() {
        var log = makeLog()
        log.record(.scroll(app: "Safari", direction: .down, distance: 100), at: at(0))
        log.record(.scroll(app: "Safari", direction: .down, distance: 40), at: at(2))  // 距前 2s > 1s
        XCTAssertEqual(log.lines.count, 2)
    }

    func testDifferentEventTypesDoNotMerge() {
        var log = makeLog()
        log.record(.type(field: "AXTextArea", text: "a"), at: at(0))
        log.record(.scroll(app: "X", direction: .down, distance: 10), at: at(0.1))
        log.record(.focus(app: "Y", window: "W"), at: at(0.2))
        XCTAssertEqual(log.lines.count, 3)
    }
}
