import XCTest
import CoPartnerCore
import ActionExecutor

/// step 55 ①：主 app ↔ XPC service 的線上契約。
///
/// 這組測試守的是**沙箱防線的前提**。跨程序連線本身盲寫、只能真機驗，
/// 但「線上到底能承載什麼」是純值問題，必須在 CI 就釘死——
/// 契約鬆掉的話（多一個命令字串欄位、UI 動作被悄悄接受），
/// 後面 sbpl profile 寫得再嚴都沒有意義。
final class ExecutionWireTests: XCTestCase {

    // MARK: - I4：沒有 shell 字串通道

    /// shell 類動作只能是 argv 陣列。這條測試釘住的是「service 端拿不到原料
    /// 去拼一個字串丟給 sh -c」——不是文風要求，是防線本身。
    func testShellCarriesArgvArrayNotAString() throws {
        let request = try ExecutionRequest.from(
            action: ProposedAction(kind: .shell(argv: ["ls", "-la", "/tmp"])),
            generation: 3)
        guard case let .shell(argv) = request.kind else { return XCTFail("應為 shell kind") }
        XCTAssertEqual(argv, ["ls", "-la", "/tmp"])

        // JSON 裡也必須是陣列——若哪天有人「順手」加了字串欄位，這條會紅。
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: ExecutionWire.encode(request)) as? [String: Any])
        let flat = String(describing: json)
        XCTAssertFalse(flat.contains("ls -la /tmp"), "線上不可出現拼好的整串命令：\(flat)")
    }

    /// 含空白 / metacharacter 的參數必須原樣保留為**一個** argv 元素，
    /// 不可在編解碼過程中被切開或被合併——那正是 shell injection 的入口。
    func testArgvElementsSurviveRoundTripIntact() throws {
        let nasty = ["echo", "a b; rm -rf /", "$(whoami)", "|", "&&"]
        let request = ExecutionRequest(actionID: UUID(), generation: 1, kind: .shell(argv: nasty))
        let decoded = try ExecutionWire.decodeRequest(ExecutionWire.encode(request))
        guard case let .shell(argv) = decoded.kind else { return XCTFail("應為 shell kind") }
        XCTAssertEqual(argv, nasty, "argv 元素邊界不可在線上被改變")
    }

    // MARK: - R2：UI 類動作不走沙箱路徑

    /// UI 動作必須**明確失敗**，不可被靜默忽略——靜默忽略會讓 HUD 顯示「已執行」
    /// 而實際什麼都沒發生。
    func testUIActionsAreRejectedNotSilentlyDropped() {
        let uiKinds: [ProposedAction.Kind] = [
            .screenshot, .click(x: 1, y: 2), .typeText("hi"),
            .keypress("cmd+s"), .scroll(dx: 0, dy: 3),
            .outboundComms(kind: "email", target: "a@b.c"),
        ]
        for kind in uiKinds {
            XCTAssertThrowsError(
                try ExecutionRequest.from(action: ProposedAction(kind: kind), generation: 1),
                "\(kind.summary) 不該被接受成沙箱請求"
            ) { error in
                guard case ExecutionWireError.notSandboxable = error else {
                    return XCTFail("錯誤型別不對：\(error)")
                }
            }
        }
    }

    /// 對照組：可沙箱化的三種動作都要過得去。
    func testSandboxableActionsAreAccepted() throws {
        let kinds: [ProposedAction.Kind] = [
            .shell(argv: ["ls"]),
            .readFile(path: "/tmp/a.txt"),
            .writeFile(path: "/tmp/a.txt", contents: "x"),
        ]
        for kind in kinds {
            XCTAssertNoThrow(try ExecutionRequest.from(action: ProposedAction(kind: kind),
                                                       generation: 1))
        }
    }

    // MARK: - 稽核關聯欄位

    /// actionID / generation 要原樣帶過去（I9 稽核關聯）。
    func testAuditCorrelationFieldsSurviveRoundTrip() throws {
        let action = ProposedAction(kind: .readFile(path: "/tmp/x"))
        let request = try ExecutionRequest.from(action: action, generation: 7)
        let decoded = try ExecutionWire.decodeRequest(ExecutionWire.encode(request))
        XCTAssertEqual(decoded.actionID, action.id)
        XCTAssertEqual(decoded.generation, 7)
    }

    // MARK: - 自檢是專屬種類，不是借來的動作

    /// 自檢入口用專屬 kind，第 ④ 段接上真執行之後才不可能夾帶真動作。
    func testSelfTestIsItsOwnKind() {
        XCTAssertEqual(ExecutionRequest.selfTest().kind, .selfTest)
    }

    /// 自檢請求**組不出**任何 shell/檔案動作——這是它不能變成後門的結構理由。
    func testSelfTestCarriesNoActionPayload() throws {
        let decoded = try ExecutionWire.decodeRequest(
            ExecutionWire.encode(ExecutionRequest.selfTest()))
        switch decoded.kind {
        case .selfTest: break
        case .shell, .readFile, .writeFile: XCTFail("自檢不可帶動作內容")
        }
    }

    // MARK: - 回覆

    func testOutcomeRoundTrips() throws {
        let outcomes: [ExecutionOutcome] = [
            .acknowledgedNotExecuted(detail: "骨架階段"),
            .rejected(reason: "解碼失敗"),
            .diagnostics(SelfTestReport(servicePID: 1234, serviceEUID: 501,
                                        serviceBundleID: "com.example.svc",
                                        willExecuteActions: false,
                                        verifiesCallerSignature: false,
                                        callerVerificationDetail: "未啟用（無 Team ID）")),
        ]
        for outcome in outcomes {
            XCTAssertEqual(try ExecutionWire.decodeOutcome(ExecutionWire.encode(outcome)), outcome)
        }
    }

    /// 壞資料要 throw，不可解出一個「看起來正常」的結果。
    func testGarbageDataThrows() {
        XCTAssertThrowsError(try ExecutionWire.decodeOutcome(Data([0x00, 0x01, 0x02])))
        XCTAssertThrowsError(try ExecutionWire.decodeRequest(Data("{}".utf8)))
    }
}
