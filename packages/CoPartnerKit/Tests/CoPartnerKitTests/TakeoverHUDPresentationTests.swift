import XCTest
import CoPartnerCore
import ActionExecutor

/// 接手 HUD 的顯示邏輯（step 53）。
///
/// 這些測試守的是**確認閘門的前提**：閘門有沒有用，取決於使用者看到的東西是否正確。
/// 顯示錯了，閘門就形同虛設——而那種錯誤在 UI 上看起來一切正常。
final class TakeoverHUDPresentationTests: XCTestCase {

    private func present(_ kind: ProposedAction.Kind,
                         rationale: String = "",
                         policy: TakeoverContract.Policy = .confirmEach) -> TakeoverHUDPresentation {
        let action = ProposedAction(kind: kind, rationale: rationale)
        return .make(action: action,
                     risk: RiskClassifier().classify(action),
                     policy: policy)
    }

    // MARK: - 動作原文必須是本地產生的

    /// 使用者確認的必須是「實際會執行什麼」，不是模型「說」它要做什麼。
    /// 這條擋的是 T1：注入的內容讓模型描述一件事、實際提議另一件事。
    func testActionSummaryComesFromStructuredKindNotModelText() {
        let p = present(.shell(argv: ["rm", "-rf", "/tmp/x"]),
                        rationale: "只是清理一個暫存檔，很安全")
        XCTAssertTrue(p.actionSummary.contains("rm"), "原文要反映真正的 argv：\(p.actionSummary)")
        XCTAssertNotEqual(p.actionSummary, p.modelRationale)
    }

    /// 模型的說法要保留（有資訊價值）但與本地判定分開呈現。
    func testModelRationalePreservedSeparately() {
        let p = present(.click(x: 10, y: 20), rationale: "點開設定選單")
        XCTAssertEqual(p.modelRationale, "點開設定選單")
    }

    // MARK: - high 風險一定要有本地原因

    /// high 的原因由本地 RiskClassifier 產生，與模型推理無關（T1 最後防線）。
    /// 沒有原因的 high 等於叫使用者盲簽。
    func testHighRiskAlwaysCarriesLocalReason() {
        let cases: [ProposedAction.Kind] = [
            .outboundComms(kind: "email", target: "boss@example.com"),
            .shell(argv: ["rm", "-rf", "/"]),
        ]
        for kind in cases {
            let p = present(kind)
            XCTAssertEqual(p.risk, .high, "\(kind.summary) 應為 high")
            XCTAssertNotNil(p.localRiskReason, "\(kind.summary) 的 high 必須附本地原因")
            XCTAssertFalse(p.localRiskReason!.isEmpty)
        }
    }

    /// 對外通訊的原因要講清楚「以你的身分送給誰」——難撤回的動作要說得具體。
    func testOutboundCommsReasonNamesTarget() {
        let p = present(.outboundComms(kind: "email", target: "boss@example.com"))
        XCTAssertTrue(p.localRiskReason?.contains("boss@example.com") ?? false,
                      "原因要指名對象：\(p.localRiskReason ?? "nil")")
    }

    // MARK: - suggestOnly 的按鈕不可誤導

    /// suggestOnly 下狀態機的 approve() 回 nil、不鑄造 token、什麼都不會執行。
    /// HUD 若仍畫成「執行」，使用者會以為自己核准的事發生了而它沒有。
    func testSuggestOnlyDoesNotPromiseExecution() {
        let p = present(.click(x: 1, y: 2), policy: .suggestOnly)
        XCTAssertFalse(p.approveWillExecute)
        XCTAssertTrue(p.approveTitle.contains("不會執行"), "按鈕文字要誠實：\(p.approveTitle)")
    }

    func testConfirmEachPromisesExecution() {
        let p = present(.click(x: 1, y: 2), policy: .confirmEach)
        XCTAssertTrue(p.approveWillExecute)
        XCTAssertEqual(p.approveTitle, "執行")
    }

    func testAutoBoundedPromisesExecution() {
        let p = present(.click(x: 1, y: 2), policy: .autoBounded)
        XCTAssertTrue(p.approveWillExecute)
    }

    /// 顯示層與狀態機不可分歧——approveWillExecute 說會執行，approve() 就該給 token。
    func testPresentationAgreesWithStateMachine() {
        for policy in [TakeoverContract.Policy.suggestOnly, .confirmEach, .autoBounded] {
            let action = ProposedAction(kind: .typeText("x"))
            let risk = RiskClassifier().classify(action)
            let p = TakeoverHUDPresentation.make(action: action, risk: risk, policy: policy)

            var model = TakeoverSessionModel(policy: policy)
            model.begin()
            _ = model.receive(action, risk: risk)
            // autoBounded + low 會自動核，不進 awaitingApproval——那條路徑不經 HUD。
            if case .awaitingApproval = model.state {
                let token = model.approve()
                XCTAssertEqual(token != nil, p.approveWillExecute,
                               "policy=\(policy)：HUD 說的與狀態機做的必須一致")
            }
        }
    }

    // MARK: - 風險標籤

    func testRiskLabelsAreDistinct() {
        let labels = [TakeoverHUDPresentation.label(for: .low),
                      TakeoverHUDPresentation.label(for: .medium),
                      TakeoverHUDPresentation.label(for: .high)]
        XCTAssertEqual(Set(labels).count, 3)
    }

    /// 低風險動作不需要本地原因，但也不該憑空捏一個。
    func testLowRiskHasNoFabricatedReason() {
        XCTAssertNil(present(.screenshot).localRiskReason)
        XCTAssertNil(present(.click(x: 1, y: 1)).localRiskReason)
    }
}
