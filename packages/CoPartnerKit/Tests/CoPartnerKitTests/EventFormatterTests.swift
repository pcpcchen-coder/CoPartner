import XCTest
import Foundation
import ScriptNarrator

/// L0 事件模板格式化（v2.1 §2）。全部離線可驗，固定 UTC 讓時間戳決定性。
final class EventFormatterTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    /// 用固定 UTC 曆建構精確到毫秒的 Date。
    private func date(_ h: Int, _ m: Int, _ s: Int, ms: Int) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 1; c.day = 1
        c.hour = h; c.minute = m; c.second = s; c.nanosecond = ms * 1_000_000
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        return cal.date(from: c)!
    }

    func testFocusLine() {
        let line = EventFormatter.line(.focus(app: "Xcode", window: "EMSController.swift"),
                                       at: date(14, 30, 2, ms: 110), timeZone: utc)
        XCTAssertEqual(line, "[14:30:02.110] FOCUS   app=Xcode win=\"EMSController.swift\"")
    }

    func testTypeLine() {
        let line = EventFormatter.line(.type(field: "AXTextArea", text: "func reconnectWebSocket() {"),
                                       at: date(14, 30, 5, ms: 400), timeZone: utc)
        XCTAssertEqual(line, "[14:30:05.400] TYPE    field=AXTextArea text=\"func reconnectWebSocket() {\"")
    }

    func testPasteLine() {
        let line = EventFormatter.line(.paste(chars: 58, preview: "WebSocket disconnect code 1006…"),
                                       at: date(14, 30, 11, ms: 880), timeZone: utc)
        XCTAssertEqual(line, "[14:30:11.880] PASTE   chars=58 preview=\"WebSocket disconnect code 1006…\"")
    }

    func testSwitchLine() {
        let line = EventFormatter.line(.switchApp(app: "Safari", window: "urlsession websocket retry backoff - Google"),
                                       at: date(14, 30, 18, ms: 20), timeZone: utc)
        XCTAssertEqual(line, "[14:30:18.020] SWITCH  app=Safari win=\"urlsession websocket retry backoff - Google\"")
    }

    func testScrollLine() {
        let line = EventFormatter.line(.scroll(app: "Safari", direction: .down, distance: 1840),
                                       at: date(14, 30, 33, ms: 500), timeZone: utc)
        XCTAssertEqual(line, "[14:30:33.500] SCROLL  app=Safari dir=down dist=1840")
    }

    func testWatchLine() {
        let line = EventFormatter.line(.watch(kind: "video"), at: date(14, 30, 40, ms: 0), timeZone: utc)
        XCTAssertEqual(line, "[14:30:40.000] WATCH   video")
    }

    func testMillisecondZeroPaddedToThreeDigits() {
        let line = EventFormatter.line(.watch(kind: "video"), at: date(0, 0, 0, ms: 7), timeZone: utc)
        XCTAssertEqual(line, "[00:00:00.007] WATCH   video")
    }

    func testFieldStartColumnsAlignAcrossEventTypes() {
        // 關鍵字補到 8 字寬 → 所有事件的欄位起點對齊在同一欄。
        let t = date(1, 2, 3, ms: 4)
        let focus = EventFormatter.line(.focus(app: "A", window: "W"), at: t, timeZone: utc)
        let scroll = EventFormatter.line(.scroll(app: "A", direction: .up, distance: 1), at: t, timeZone: utc)
        func fieldColumn(_ line: String) -> Int? { line.range(of: "app=").map { line.distance(from: line.startIndex, to: $0.lowerBound) } }
        XCTAssertEqual(fieldColumn(focus), fieldColumn(scroll))
    }
}
