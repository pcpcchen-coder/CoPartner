import XCTest
import Foundation
import CoPartnerCore
import ActionExecutor

/// step 53.1：主 app ↔ XPC service 的線上契約。
///
/// 這組測試守的是**沙箱防線的前提**。跨程序連線本身盲寫、只能真機驗，
/// 但「線上到底能承載什麼」是純值問題，必須在 CI 就釘死——
/// 契約鬆掉的話（多一個命令字串欄位、UI 動作被悄悄接受），
/// 後面 sbpl profile 寫得再嚴都沒有意義。
final class ExecutionWireTests: XCTestCase {

    /// 測試用的沙箱設定。真實情況由 `SandboxWorkspace.forContract` 從**本地固定表**產生。
    private static let workspace = SandboxWorkspace(
        root: "/tmp/ws", execAllowlist: ["/bin/cat"], deniedSubpaths: [])

    /// shell 動作沒帶沙箱設定時必須明確失敗——預設值在這裡沒有安全的選項。
    func testShellWithoutWorkspaceIsRejected() {
        XCTAssertThrowsError(
            try ExecutionRequest.from(action: ProposedAction(kind: .shell(argv: ["/bin/cat"])),
                                      generation: 1)
        ) { error in
            guard case ExecutionWireError.missingWorkspace = error else {
                return XCTFail("錯誤型別不對：\(error)")
            }
        }
    }

    // MARK: - I4：沒有 shell 字串通道

    /// shell 類動作只能是 argv 陣列。這條測試釘住的是「service 端拿不到原料
    /// 去拼一個字串丟給 sh -c」——不是文風要求，是防線本身。
    func testShellCarriesArgvArrayNotAString() throws {
        let request = try ExecutionRequest.from(
            action: ProposedAction(kind: .shell(argv: ["ls", "-la", "/tmp"])),
            generation: 3, workspace: Self.workspace)
        guard case let .shell(argv, _) = request.kind else { return XCTFail("應為 shell kind") }
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
        let request = ExecutionRequest(actionID: UUID(), generation: 1,
                                       kind: .shell(argv: nasty, workspace: Self.workspace))
        let decoded = try ExecutionWire.decodeRequest(ExecutionWire.encode(request))
        guard case let .shell(argv, _) = decoded.kind else { return XCTFail("應為 shell kind") }
        XCTAssertEqual(argv, nasty, "argv 元素邊界不可在線上被改變")
    }

    // MARK: - R2：UI 類動作不走沙箱路徑

    /// UI 動作必須**明確失敗**，不可被靜默忽略——靜默忽略會讓 HUD 顯示「已執行」
    /// 而實際什麼都沒發生。
    func testUIActionsAreRejectedNotSilentlyDropped() {
        let uiKinds: [ProposedAction.Kind] = [
            .screenshot, .click(x: 1, y: 2), .typeText("hi"),
            .keypress("cmd+s"), .scroll(x: 5, y: 6, dx: 0, dy: 3),
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
        // 刻意逐一列出而不用 default：新增 kind 時這裡會編譯失敗，
        // 強迫作者回來想「這個新種類算不算帶動作內容」。
        // 用 default 的話新 kind 會被靜默歸類成「不帶動作」——那正是最危險的預設。
        case .shell, .readFile, .writeFile, .dryRun: XCTFail("自檢不可帶動作內容")
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
            .executed(ExecutionReport(disposition: "succeeded", didExecute: true,
                                      stdout: "hi", stderr: "")),
        ]
        for outcome in outcomes {
            XCTAssertEqual(try ExecutionWire.decodeOutcome(ExecutionWire.encode(outcome)), outcome)
        }
    }

    // MARK: - 探測腳本與線上型別必須對得起來

    /// `scripts/xpc-probe.swift` 裡的 JSON 是**手寫**的（那個腳本刻意獨立，
    /// 不依賴 CoPartnerKit，才能用 swiftc 單獨編成 ad-hoc 簽章的外部程序）。
    ///
    /// 手寫就會漂：Kind 一旦改名或改形狀，腳本會靜默送出解不開的請求，
    /// 而失敗長得像「service 拒收」——看起來像防線生效，其實是腳本壞了。
    /// 那正好會讓拒絕路徑的驗收得出**假的通過**。
    ///
    /// 這條測試直接讀那個檔、抽出裡面的 JSON 字面值來解，讓 CI 綁住兩者。
    func testProbeScriptPayloadStillDecodes() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // CoPartnerKitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // CoPartnerKit
            .deletingLastPathComponent()   // packages
            .deletingLastPathComponent()   // repo root
        let script = repoRoot.appendingPathComponent("scripts/xpc-probe.swift")
        let source = try String(contentsOf: script, encoding: .utf8)

        // 抽出 `let payload = Data(#"…"#.utf8)` 裡的字面值。
        guard let line = source.split(separator: "\n").first(where: { $0.contains("let payload") }),
              let start = line.range(of: "#\""),
              let end = line.range(of: "\"#", range: start.upperBound..<line.endIndex) else {
            return XCTFail("在 \(script.path) 找不到 payload 字面值——腳本結構變了，請同步更新這條測試")
        }
        let json = String(line[start.upperBound..<end.lowerBound])

        let request = try ExecutionWire.decodeRequest(Data(json.utf8))
        XCTAssertEqual(request.kind, .selfTest,
                       "探測腳本送的必須仍是 selfTest（絕不可變成真動作）")
    }

    /// 反向釘住合成編碼的實際形狀。
    ///
    /// 上面那條保證腳本解得開，但若哪天 `Kind` 的編碼形狀變了、而腳本也「剛好」
    /// 被一起改對，就看不出契約已經不同。這條把形狀本身寫死成期望值——
    /// Swift 對 enum 的 Codable 合成規則是外部行為，不該只存在於我腦中的假設。
    func testSelfTestEncodesAsSingleEmptyKeyedCase() throws {
        let data = try ExecutionWire.encode(ExecutionRequest.selfTest())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let kind = try XCTUnwrap(object["kind"] as? [String: Any])
        XCTAssertEqual(Array(kind.keys), ["selfTest"])
        XCTAssertEqual((kind["selfTest"] as? [String: Any])?.count, 0,
                       "無關聯值的 case 應編成空物件")
    }

    // MARK: - 乾跑（step 53.4-B）

    /// 乾跑是**專屬 kind**，不是 `shell` 上的旗標。
    /// 旗標會有預設值，而預設值寫錯的方向是「以為在乾跑、其實執行了」。
    func testDryRunIsItsOwnKindNotAFlagOnShell() throws {
        let request = ExecutionRequest(actionID: UUID(), generation: 0,
                                       kind: .dryRun(argv: ["/bin/cat"], workspace: Self.workspace))
        let decoded = try ExecutionWire.decodeRequest(ExecutionWire.encode(request))
        switch decoded.kind {
        case .dryRun: break
        case .shell, .readFile, .writeFile, .selfTest:
            XCTFail("乾跑不可被解成別的 kind")
        }
    }

    /// 乾跑報告要能原樣往返——它是給人看的證據，欄位掉了就等於證據被改過。
    func testDryRunReportRoundTrips() throws {
        let report = DryRunReport(
            allowedByAllowlist: true, rejectionReason: nil,
            spawnArguments: ["/usr/bin/sandbox-exec", "-f", "/ws/p.sb", "/bin/cat", "a b"],
            profile: "(version 1)\n(deny default)", environment: ["PATH=", "HOME=/ws"])
        let decoded = try ExecutionWire.decodeOutcome(ExecutionWire.encode(.dryRun(report)))
        XCTAssertEqual(decoded, .dryRun(report))
    }

    /// argv 在報告裡是**陣列**，不是拼好的字串。
    /// 印成一行的話，帶空白的參數看起來會像兩個——而那正好是最需要看清楚的地方。
    func testDryRunKeepsArgumentsAsArray() throws {
        let report = DryRunReport(allowedByAllowlist: true, rejectionReason: nil,
                                  spawnArguments: ["/bin/cat", "a b; rm -rf /"],
                                  profile: "", environment: [])
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: ExecutionWire.encode(.dryRun(report)))
            as? [String: Any])
        XCTAssertFalse(String(describing: json).contains("/bin/cat a b"),
                       "argv 不可被拼成一行")
    }

    /// 壞資料要 throw，不可解出一個「看起來正常」的結果。
    func testGarbageDataThrows() {
        XCTAssertThrowsError(try ExecutionWire.decodeOutcome(Data([0x00, 0x01, 0x02])))
        XCTAssertThrowsError(try ExecutionWire.decodeRequest(Data("{}".utf8)))
    }
}
