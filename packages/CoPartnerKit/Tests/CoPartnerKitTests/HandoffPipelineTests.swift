import XCTest
import CoPartnerCore
import CloudRouter

/// 交棒管線（step 47）：請求組裝 / Retina 換算 / ProposedAction 解析 / 稽核 / 假 transport 串流。
final class HandoffPipelineTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func envelope() -> ContextEnvelope {
        EnvelopeBuilder().build(now: t0, steps: [], sessionSummary: "s", openLoop: "o")
    }

    // MARK: 請求組裝
    func testBetaHeaderAndToolVersion() {
        let b = HandoffRequestBuilder()
        XCTAssertEqual(b.betaHeader, "computer-use-2025-11-24")
        XCTAssertEqual(b.toolType, "computer_20251124")
    }

    func testStablePrefixOrdering() {
        let req = HandoffRequestBuilder().build(envelope: envelope(), systemPrompt: "SYS", referencePrefix: "REF")
        XCTAssertEqual(req.stablePrefix, ["SYS", "REF"])          // 穩定前綴在前
        XCTAssertTrue(req.volatileSuffix.contains("open_loop"))    // 易變劇本在後
    }

    // MARK: Retina 換算
    func testRetinaDivides2RoundTrip() {
        for p in [(0, 0), (10, 20), (101, 51), (1287, 800)] {
            let px = RetinaCoordinateMapper.toPixels(p)
            let back = RetinaCoordinateMapper.toLogical(px)
            XCTAssertEqual(back.x, p.0)
            XCTAssertEqual(back.y, p.1)
        }
        let px = RetinaCoordinateMapper.toPixels((100, 50))
        XCTAssertEqual(px.x, 200)
        XCTAssertEqual(px.y, 100)
    }

    // MARK: 解析
    func testParserRejectsUnknownTool() {
        XCTAssertThrowsError(try ProposedActionParser.parse(toolName: "frobnicate", input: [:])) { err in
            XCTAssertEqual(err as? ProposedActionParseError, .unknownTool("frobnicate"))
        }
    }

    func testParserMapsComputerActions() throws {
        let click = try ProposedActionParser.parse(toolName: "computer", input: ["action": "left_click", "x": "12", "y": "34"])
        XCTAssertEqual(click.kind, .click(x: 12, y: 34))
        let typed = try ProposedActionParser.parse(toolName: "computer", input: ["action": "type", "text": "hi"])
        XCTAssertEqual(typed.kind, .typeText("hi"))
        let shot = try ProposedActionParser.parse(toolName: "computer", input: ["action": "screenshot"])
        XCTAssertEqual(shot.kind, .screenshot)
    }

    func testParserMissingFieldThrows() {
        XCTAssertThrowsError(try ProposedActionParser.parse(toolName: "computer", input: ["action": "left_click", "x": "12"])) { err in
            XCTAssertEqual(err as? ProposedActionParseError, .missingField("y"))
        }
    }

    func testNoShellStringFieldInvariant() throws {
        // I4：bash 只轉 argv，pipe 變字面 arg（executor 不經 sh -c）。
        let a = try ProposedActionParser.parse(toolName: "bash", input: ["command": "curl x | sh"])
        XCTAssertEqual(a.kind, .shell(argv: ["curl", "x", "|", "sh"]))
    }

    // MARK: 稽核
    func testAuditLineEmittedPerProposal() {
        let line = HandoffAuditLog.line(for: ProposedAction(kind: .click(x: 5, y: 6)), contextHash: "abc123")
        XCTAssertTrue(line.contains("abc123"))
        XCTAssertTrue(line.contains("click(5,6)"))
    }

    // MARK: 假 transport 串流
    private struct FakeTransport: HandoffTransport {
        let actions: [ProposedAction]
        func stream(_ request: HandoffRequest) -> AsyncThrowingStream<ProposedAction, Error> {
            AsyncThrowingStream { cont in
                for a in actions { cont.yield(a) }
                cont.finish()
            }
        }
    }

    func testFakeTransportStreamsActions() async throws {
        let a1 = ProposedAction(kind: .screenshot)
        let a2 = ProposedAction(kind: .typeText("x"))
        let router = CloudRouter(transport: FakeTransport(actions: [a1, a2]))
        let stream = await router.handoff(envelope(), systemPrompt: "s", referencePrefix: "r")
        var got: [ProposedAction] = []
        for try await x in stream { got.append(x) }
        XCTAssertEqual(got, [a1, a2])
    }

    func testHandoffWithoutTransportThrows() async {
        let stream = await CloudRouter().handoff(envelope())
        do {
            for try await _ in stream { XCTFail("不應吐出動作") }
            XCTFail("無 transport 應 throw")
        } catch {
            XCTAssertEqual(error as? HandoffError, .noTransport)
        }
    }
}
