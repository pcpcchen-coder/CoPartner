import XCTest
import CoPartnerCore
import ActionExecutor

/// Undo stack（step 52，威脅 T9）：LIFO 回退、barrier 止步、新 handoff 開新 scope。
final class UndoStackTests: XCTestCase {
    private func inverse(_ path: String) -> ProposedAction {
        ProposedAction(kind: .writeFile(path: path, contents: "原內容"))
    }

    func testUndoLIFOOrder() {
        var stack = UndoStack()
        stack.push(.restorable(id: UUID(), inverse: inverse("/a")))
        stack.push(.restorable(id: UUID(), inverse: inverse("/b")))
        XCTAssertEqual(stack.popUndo()?.kind, .writeFile(path: "/b", contents: "原內容"))   // 後進先出
        XCTAssertEqual(stack.popUndo()?.kind, .writeFile(path: "/a", contents: "原內容"))
        XCTAssertNil(stack.popUndo())
    }

    func testBarrierStopsUndo() {
        var stack = UndoStack()
        stack.push(.restorable(id: UUID(), inverse: inverse("/a")))
        stack.push(.barrier(id: UUID(), label: "已寄出郵件（無法復原）"))
        XCTAssertFalse(stack.canUndo)
        XCTAssertNil(stack.popUndo())            // barrier 止步：不越過去回退 /a
        XCTAssertEqual(stack.count, 2)           // 什麼都沒彈出
    }

    func testEmptyUndoNoop() {
        var stack = UndoStack()
        XCTAssertFalse(stack.canUndo)
        XCTAssertNil(stack.popUndo())
    }

    func testNewHandoffScopesStack() {
        var stack = UndoStack()
        stack.push(.restorable(id: UUID(), inverse: inverse("/old")))
        stack.beginScope()                       // 新 handoff
        XCTAssertEqual(stack.count, 0)
        XCTAssertNil(stack.popUndo())
    }

    func testRestorableProducesInverseAction() {
        var stack = UndoStack()
        let inv = inverse("/doc.txt")
        stack.push(.restorable(id: UUID(), inverse: inv))
        XCTAssertTrue(stack.canUndo)
        XCTAssertEqual(stack.popUndo(), inv)
    }
}
