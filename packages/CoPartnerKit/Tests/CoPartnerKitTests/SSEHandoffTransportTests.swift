import XCTest
import CoPartnerCore
import CloudRouter

/// 交棒 transport 的三層解析（step 53）：SSE 框架 → Anthropic 語意 → ProposedAction。
///
/// 這些測試用**假 SSE 來源重播真實形狀的腳本**——真 HTTP 是注入點，
/// 但「串流怎麼被切、tool_use 的 input 怎麼跨事件拼回來」是純邏輯，CI 驗得到，
/// 而且正是最容易寫錯的地方。
final class SSEHandoffTransportTests: XCTestCase {

    // MARK: - 第一層：SSE 框架

    func testParsesSingleFrame() {
        var p = SSEFrameParser()
        let frames = p.feed("event: message_start\ndata: {\"a\":1}\n\n")
        XCTAssertEqual(frames, [SSEFrame(event: "message_start", data: "{\"a\":1}")])
    }

    /// 網路 chunk 邊界是任意的——一個 frame 被切成兩半是常態，不是異常。
    func testFrameSplitAcrossChunks() {
        var p = SSEFrameParser()
        XCTAssertTrue(p.feed("event: content_bl").isEmpty)
        XCTAssertTrue(p.feed("ock_delta\ndata: {\"x\"").isEmpty)
        let frames = p.feed(":1}\n\n")
        XCTAssertEqual(frames, [SSEFrame(event: "content_block_delta", data: "{\"x\":1}")])
    }

    /// 一個 chunk 內含多個 frame 也要全部吐出。
    func testMultipleFramesInOneChunk() {
        var p = SSEFrameParser()
        let frames = p.feed("data: one\n\ndata: two\n\ndata: three\n\n")
        XCTAssertEqual(frames.map(\.data), ["one", "two", "three"])
    }

    /// 註解行是 keep-alive 心跳，不可當成資料。
    func testCommentLinesIgnored() {
        var p = SSEFrameParser()
        let frames = p.feed(": ping\n: ping\ndata: real\n\n")
        XCTAssertEqual(frames, [SSEFrame(event: nil, data: "real")])
    }

    func testCRLFHandled() {
        var p = SSEFrameParser()
        let frames = p.feed("event: e\r\ndata: d\r\n\r\n")
        XCTAssertEqual(frames, [SSEFrame(event: "e", data: "d")])
    }

    /// 規範：冒號後**一個**空格去掉，多的保留（data 內容可能刻意有前導空白）。
    func testOnlyOneLeadingSpaceStripped() {
        XCTAssertEqual(SSEFrameParser.splitField("data:  two-spaces").value, " two-spaces")
        XCTAssertEqual(SSEFrameParser.splitField("data:none").value, "none")
    }

    func testMultiLineDataJoinedWithNewline() {
        var p = SSEFrameParser()
        let frames = p.feed("data: line1\ndata: line2\n\n")
        XCTAssertEqual(frames.first?.data, "line1\nline2")
    }

    // MARK: - 第二層：tool_use 跨事件拼裝

    /// input 是分批送的、可能切在 JSON token 中間——收齊才能解析。
    /// 逐事件解析必然失敗，這條釘住累積行為。
    func testToolInputAccumulatedAcrossDeltas() throws {
        var d = AnthropicStreamDecoder()
        _ = try d.feed(frame(#"{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_1","name":"computer","input":{}}}"#))
        _ = try d.feed(frame(#"{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"action\":\"left_"}}"#))
        _ = try d.feed(frame(#"{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"click\",\"coordinate\":[12,34]}"}}"#))
        let done = try d.feed(frame(#"{"type":"content_block_stop","index":0}"#))

        XCTAssertEqual(done.count, 1)
        XCTAssertEqual(done.first?.toolName, "computer")
        XCTAssertEqual(done.first?.input["action"] as? String, "left_click")
    }

    /// input 為空物件時 Anthropic 可能一個 delta 都不送——那是合法的，不是錯誤。
    func testEmptyInputWithNoDeltasIsNotAnError() throws {
        var d = AnthropicStreamDecoder()
        _ = try d.feed(frame(#"{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"t","name":"computer","input":{}}}"#))
        let done = try d.feed(frame(#"{"type":"content_block_stop","index":0}"#))
        XCTAssertEqual(done.count, 1)
        XCTAssertTrue(done[0].input.isEmpty)
    }

    /// 同一則訊息可以有多個平行區塊，必須依 index 分開累積、不可互相污染。
    func testParallelBlocksTrackedByIndex() throws {
        var d = AnthropicStreamDecoder()
        _ = try d.feed(frame(#"{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"a","name":"computer","input":{}}}"#))
        _ = try d.feed(frame(#"{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"b","name":"bash","input":{}}}"#))
        _ = try d.feed(frame(#"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"command\":\"ls\"}"}}"#))
        _ = try d.feed(frame(#"{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"action\":\"screenshot\"}"}}"#))

        let first = try d.feed(frame(#"{"type":"content_block_stop","index":1}"#))
        XCTAssertEqual(first.first?.toolName, "bash")
        XCTAssertEqual(first.first?.input["command"] as? String, "ls")

        let second = try d.feed(frame(#"{"type":"content_block_stop","index":0}"#))
        XCTAssertEqual(second.first?.toolName, "computer")
        XCTAssertEqual(second.first?.input["action"] as? String, "screenshot")
    }

    /// 文字區塊成為後續動作的 rationale——HUD 要顯示「為什麼要做這個」。
    func testTextBlockBecomesRationale() throws {
        var d = AnthropicStreamDecoder()
        _ = try d.feed(frame(#"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#))
        _ = try d.feed(frame(#"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"先截圖確認畫面"}}"#))
        _ = try d.feed(frame(#"{"type":"content_block_stop","index":0}"#))
        _ = try d.feed(frame(#"{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"t","name":"computer","input":{}}}"#))
        _ = try d.feed(frame(#"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"action\":\"screenshot\"}"}}"#))
        let done = try d.feed(frame(#"{"type":"content_block_stop","index":1}"#))
        XCTAssertEqual(done.first?.rationale, "先截圖確認畫面")
    }

    func testMalformedToolInputThrows() {
        var d = AnthropicStreamDecoder()
        _ = try? d.feed(frame(#"{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"t","name":"computer","input":{}}}"#))
        _ = try? d.feed(frame(#"{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{not json"}}"#))
        XCTAssertThrowsError(try d.feed(frame(#"{"type":"content_block_stop","index":0}"#)))
    }

    func testStopReasonCaptured() throws {
        var d = AnthropicStreamDecoder()
        _ = try d.feed(frame(#"{"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":9}}"#))
        XCTAssertEqual(d.stopReason, "tool_use")
    }

    // MARK: - 全鏈：假 SSE 來源 → ProposedAction

    func testEndToEndProducesProposedActions() async throws {
        let transport = SSEHandoffTransport(source: FakeSSESource(script: Self.twoActionScript))
        var got: [ProposedAction] = []
        for try await a in transport.stream(Self.request()) { got.append(a) }
        XCTAssertEqual(got.map(\.kind), [.screenshot, .click(x: 500, y: 300)])
    }

    /// 逐**字元**餵——最嚴苛的切法，驗證沒有任何地方假設 chunk 邊界對齊 frame。
    /// 注意 `joined()`：直接對 [String] 做 map(String.init) 只是 String→String，
    /// 什麼都沒切到，測試會假通過。
    func testEndToEndSurvivesCharacterByCharacterChunking() async throws {
        let chars = Self.twoActionScript.joined().map(String.init)
        let transport = SSEHandoffTransport(source: FakeSSESource(script: chars))
        var got: [ProposedAction] = []
        for try await a in transport.stream(Self.request()) { got.append(a) }
        XCTAssertEqual(got.map(\.kind), [.screenshot, .click(x: 500, y: 300)])
    }

    /// 不支援的動作（例如 zoom）預設略過、其餘照常——
    /// 單一個不認得的提議不該讓整次接手作廢；但也絕不代換成別的動作。
    func testUnsupportedActionIsSkippedNotSubstituted() async throws {
        let script = [
            Self.sse(#"{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"a","name":"computer","input":{}}}"#),
            Self.sse(#"{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"action\":\"zoom\",\"region\":[1,2,3,4]}"}}"#),
            Self.sse(#"{"type":"content_block_stop","index":0}"#),
            Self.sse(#"{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"b","name":"computer","input":{}}}"#),
            Self.sse(#"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"action\":\"screenshot\"}"}}"#),
            Self.sse(#"{"type":"content_block_stop","index":1}"#),
        ]
        let transport = SSEHandoffTransport(source: FakeSSESource(script: script))
        var got: [ProposedAction] = []
        for try await a in transport.stream(Self.request()) { got.append(a) }
        XCTAssertEqual(got.map(\.kind), [.screenshot], "zoom 應被略過，screenshot 照常吐出")
    }

    /// 需要嚴格模式時可改成整串中止。
    func testFailFastModeThrowsOnUnsupportedAction() async {
        let script = [
            Self.sse(#"{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"a","name":"computer","input":{}}}"#),
            Self.sse(#"{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"action\":\"zoom\"}"}}"#),
            Self.sse(#"{"type":"content_block_stop","index":0}"#),
        ]
        let transport = SSEHandoffTransport(source: FakeSSESource(script: script),
                                            failOnUnparsableAction: true)
        do {
            for try await _ in transport.stream(Self.request()) { XCTFail("不應吐出動作") }
            XCTFail("嚴格模式應 throw")
        } catch {
            // 預期
        }
    }

    func testSourceErrorPropagates() async {
        let transport = SSEHandoffTransport(source: FailingSSESource())
        do {
            for try await _ in transport.stream(Self.request()) { XCTFail("不應吐出動作") }
            XCTFail("來源錯誤應 throw")
        } catch {
            // 預期
        }
    }

    // MARK: - helpers

    private func frame(_ json: String) -> SSEFrame { SSEFrame(event: nil, data: json) }
    /// 只留 static 版本——同名的 instance + static 多載在不同情境會解析到不同的那個，
    /// 是沒必要的歧義來源。
    private static func sse(_ json: String) -> String { "data: \(json)\n\n" }

    private static func request() -> HandoffRequest {
        HandoffRequestBuilder(displayWidthPx: 1440, displayHeightPx: 900)
            .build(envelope: EnvelopeBuilder().build(now: Date(timeIntervalSince1970: 1_000_000),
                                                     steps: [], sessionSummary: "s", openLoop: "o"),
                   systemPrompt: "SYS", referencePrefix: "REF")
    }

    /// 一段 screenshot + 一次點擊的真實形狀腳本。
    private static let twoActionScript: [String] = [
        sse(#"{"type":"message_start","message":{"id":"msg_1"}}"#),
        sse(#"{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"a","name":"computer","input":{}}}"#),
        sse(#"{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"action\":\"screenshot\"}"}}"#),
        sse(#"{"type":"content_block_stop","index":0}"#),
        sse(#"{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"b","name":"computer","input":{}}}"#),
        sse(#"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"action\":\"left_click\","}}"#),
        sse(#"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"\"coordinate\":[500,300]}"}}"#),
        sse(#"{"type":"content_block_stop","index":1}"#),
        sse(#"{"type":"message_delta","delta":{"stop_reason":"tool_use"}}"#),
        sse(#"{"type":"message_stop"}"#),
    ]
}

/// 重播固定腳本的假 SSE 來源。真 HTTP 在同一個 protocol 上注入（🔒 待接）。
private struct FakeSSESource: SSEByteSource {
    let script: [String]
    func chunks(for request: HandoffRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            for chunk in script { continuation.yield(chunk) }
            continuation.finish()
        }
    }
}

private struct FailingSSESource: SSEByteSource {
    struct Boom: Error {}
    func chunks(for request: HandoffRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish(throwing: Boom()) }
    }
}
