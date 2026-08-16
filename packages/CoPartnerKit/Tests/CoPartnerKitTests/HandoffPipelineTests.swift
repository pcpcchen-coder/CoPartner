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
    /// 一個 1440×900 的顯示器（測試用）。真機由呼叫端從實際顯示器取值。
    private func builder(model: String = "claude-opus-5", enableZoom: Bool = false) -> HandoffRequestBuilder {
        HandoffRequestBuilder(model: model, displayWidthPx: 1440, displayHeightPx: 900, enableZoom: enableZoom)
    }

    /// 這兩個值於 2026-08-16 對照 live computer-use 文件查證過。
    /// 改動它們前請先重查 Compatibility 區塊——搭錯 header 與 tool 版本會被 API 拒絕。
    func testBetaHeaderAndToolVersion() {
        let b = builder()
        XCTAssertEqual(b.betaHeader, "computer-use-2025-11-24")
        XCTAssertEqual(b.toolType, "computer_20251124")
    }

    /// API 規定 tool 的 `name` 必須恰好是 "computer"，不是可自由命名的欄位。
    func testToolNameIsExactlyComputer() {
        XCTAssertEqual(builder().toolName, "computer")
        XCTAssertEqual(HandoffRequestBuilder.requiredToolName, "computer")
    }

    /// 顯示器尺寸必須原封不動傳到請求裡——它決定 Claude 回傳座標的意義，
    /// 填錯不會報錯，只會讓每次點擊落在錯的位置。
    func testDisplaySizeCarriedIntoRequest() {
        let req = builder().build(envelope: envelope(), systemPrompt: "SYS", referencePrefix: "REF")
        XCTAssertEqual(req.displayWidthPx, 1440)
        XCTAssertEqual(req.displayHeightPx, 900)
    }

    func testEnableZoomDefaultsOffAndIsCarried() {
        XCTAssertFalse(builder().build(envelope: envelope(), systemPrompt: "S", referencePrefix: "R").enableZoom)
        XCTAssertTrue(builder(enableZoom: true)
            .build(envelope: envelope(), systemPrompt: "S", referencePrefix: "R").enableZoom)
    }

    /// 支援模型清單（2026-08-16 查證）。較舊的模型要走 computer-use-2025-01-24 那份契約。
    func testModelSupportCheck() {
        XCTAssertTrue(builder(model: "claude-opus-5").isModelSupported)
        XCTAssertTrue(builder(model: "claude-sonnet-5").isModelSupported)
        XCTAssertFalse(builder(model: "claude-sonnet-4-5").isModelSupported,
                       "Sonnet 4.5 需 computer-use-2025-01-24，不在本 builder 的契約內")
        XCTAssertFalse(builder(model: "gpt-4").isModelSupported)
    }

    func testStablePrefixOrdering() {
        let req = builder().build(envelope: envelope(), systemPrompt: "SYS", referencePrefix: "REF")
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
        let router = CloudRouter(transport: FakeTransport(actions: [a1, a2]),
                                 requestBuilder: builder())
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

    /// 有 transport 但沒設定 builder → 明確失敗，不可拿假的螢幕尺寸矇混過去
    /// （填錯 display size 不會報錯，只會讓 Claude 的座標全部偏掉）。
    func testHandoffWithoutRequestBuilderThrows() async {
        let router = CloudRouter(transport: FakeTransport(actions: [ProposedAction(kind: .screenshot)]))
        let stream = await router.handoff(envelope())
        do {
            for try await _ in stream { XCTFail("不應吐出動作") }
            XCTFail("無 requestBuilder 應 throw")
        } catch {
            XCTAssertEqual(error as? HandoffError, .noRequestBuilder)
        }
    }
}
