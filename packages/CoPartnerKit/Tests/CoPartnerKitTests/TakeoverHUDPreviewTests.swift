import XCTest
import CoPartnerCore
import ActionExecutor

/// step 54：HUD 版面預覽（除錯入口）的安全不變式。
///
/// 一顆「叫出浮層」的除錯按鈕，做錯了就是繞過確認閘門的後門。
/// 這組測試釘住三件事：預覽**不會執行**、預覽**分得出來**、
/// 而且預覽走的是**真的產生路徑**（否則預覽通過也不代表真提議長這樣）。
final class TakeoverHUDPreviewTests: XCTestCase {

    // MARK: - 預覽不會執行

    /// 最重要的一條：預覽的主要按鈕永遠不承諾執行。
    func testPreviewNeverPromisesExecution() {
        XCTAssertFalse(TakeoverHUDPresentation.previewFixture().approveWillExecute)
    }

    /// 即使 policy 是會執行的 confirmEach / autoBounded，isPreview 仍必須壓過它。
    /// （`make` 裡那條 `&& !isPreview` 就是這條測試在守。）
    func testPreviewOverridesExecutingPolicies() {
        let action = ProposedAction(kind: .click(x: 10, y: 10))
        for policy in [TakeoverContract.Policy.confirmEach, .autoBounded, .suggestOnly] {
            let p = TakeoverHUDPresentation.make(action: action, risk: .low,
                                                 policy: policy, isPreview: true)
            XCTAssertFalse(p.approveWillExecute, "預覽在 \(policy) 下仍不可承諾執行")
            XCTAssertFalse(p.approveTitle.contains("執行") && !p.approveTitle.contains("不會執行"),
                           "預覽按鈕文字不可讀起來像會執行：\(p.approveTitle)")
        }
    }

    /// 對照組：非預覽的行為完全沒被改動（加旗標不可改到真路徑）。
    func testNonPreviewBehaviourUnchanged() {
        let action = ProposedAction(kind: .click(x: 1, y: 2))
        let confirm = TakeoverHUDPresentation.make(action: action, risk: .low, policy: .confirmEach)
        XCTAssertTrue(confirm.approveWillExecute)
        XCTAssertEqual(confirm.approveTitle, "執行")
        XCTAssertFalse(confirm.isPreview)

        let suggest = TakeoverHUDPresentation.make(action: action, risk: .low, policy: .suggestOnly)
        XCTAssertFalse(suggest.approveWillExecute)
        XCTAssertEqual(suggest.approveTitle, "僅建議（不會執行）")
    }

    // MARK: - 預覽分得出來

    /// UI 靠這個旗標畫黃色橫幅。旗標沒立 → 預覽和真提議長得一模一樣，
    /// 使用者可能反過來把真提議當成預覽而盲按執行。
    func testPreviewIsFlagged() {
        XCTAssertTrue(TakeoverHUDPresentation.previewFixture().isPreview)
        XCTAssertFalse(
            TakeoverHUDPresentation.make(action: ProposedAction(kind: .screenshot),
                                         risk: .low, policy: .confirmEach).isPreview,
            "真提議不可被標成預覽——那會讓使用者以為按下去不會發生事情")
    }

    // MARK: - 預覽走真的產生路徑

    /// 樣本必須真的被本地分級器判成 high，而不是硬塞一個 high 進去。
    /// 這樣目視預覽時看到的紅色標頭，就是真提議會有的紅色標頭。
    func testPreviewFixtureIsClassifiedHighByRealClassifier() {
        let preview = TakeoverHUDPresentation.previewFixture()
        XCTAssertEqual(preview.risk, .high)
        XCTAssertEqual(preview.riskLabel, TakeoverHUDPresentation.label(for: .high))
    }

    /// high 一律要附本地原因——這正是預覽最該驗到的那條路徑
    /// （沒有原因的 high 等於叫使用者盲簽）。
    func testPreviewFixtureCarriesLocalRiskReason() {
        let reason = TakeoverHUDPresentation.previewFixture().localRiskReason
        XCTAssertNotNil(reason, "high 風險必須帶本地原因，預覽也要驗到這條")
        XCTAssertFalse(reason?.isEmpty ?? true)
    }

    /// 動作原文由結構化欄位產生，不是模型的說法——預覽也必須是同一套。
    func testPreviewSummaryComesFromStructuredFields() {
        let preview = TakeoverHUDPresentation.previewFixture()
        let expected = ProposedAction.Kind.shell(argv: ["rm", "-rf", "~/Documents/專案備份"]).summary
        XCTAssertEqual(preview.actionSummary, expected)
    }

    /// 假的理由要看得出是假的——預覽的說法不該被誤讀成 Claude 真的講過。
    func testPreviewRationaleIsMarkedAsFake() {
        XCTAssertTrue(TakeoverHUDPresentation.previewFixture().modelRationale.contains("預覽"),
                      "預覽的模型說法要自帶標示")
    }
}
