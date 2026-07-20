import XCTest
import CoPartnerCore
import ActionExecutor

/// 接手 HUD 狀態機（step 48）：Approve/Skip/Stop、token 鑄造、autoBounded 上限、I2（high 永不自動核）。
/// 註：ApprovalToken 的 init 是 internal——本測試（模組外）**無法**自行鑄造 token，
/// 只能經 approve()/自動核取得；這正是 I1「繞過閘門的路徑不存在」的編譯期證據。
final class TakeoverSessionModelTests: XCTestCase {
    private func action(_ kind: ProposedAction.Kind = .click(x: 1, y: 1)) -> ProposedAction {
        ProposedAction(kind: kind)
    }

    func testReceiveEntersAwaitingApproval() {
        var m = TakeoverSessionModel(policy: .confirmEach)
        m.begin()
        let a = action()
        let token = m.receive(a, risk: .low)
        XCTAssertNil(token)                                        // confirmEach 一律等人按
        XCTAssertEqual(m.state, .awaitingApproval(a, .low))
    }

    func testApproveMintsTokenAndExecutes() {
        var m = TakeoverSessionModel(policy: .confirmEach)
        m.begin()
        let a = action()
        _ = m.receive(a, risk: .medium)
        let token = m.approve()
        XCTAssertNotNil(token)
        XCTAssertEqual(m.state, .executing(a))
    }

    func testSkipAdvancesWithoutToken() {
        var m = TakeoverSessionModel(policy: .confirmEach)
        m.begin()
        _ = m.receive(action(), risk: .low)
        m.skip()
        XCTAssertEqual(m.state, .proposing)
    }

    func testStopAbortsAndInvalidatesGeneration() {
        let clock = HandoffGeneration()
        var m = TakeoverSessionModel(policy: .confirmEach, generationClock: clock)
        m.begin()
        _ = m.receive(action(), risk: .low)
        let token = m.approve()
        XCTAssertNotNil(token)
        m.stop()
        XCTAssertEqual(m.state, .aborted)
        // 世代已 bump——舊 token 失效的行為由 ActionExecutorSandboxTests.testStaleGenerationTokenRejected 驗。
    }

    func testHighRiskNeverAutoApproved() {
        // I2：confirmEach 與 autoBounded 下 high 都必須等人按。
        for policy in [TakeoverContract.Policy.confirmEach, .autoBounded] {
            var m = TakeoverSessionModel(policy: policy)
            m.begin()
            let a = action(.shell(argv: ["rm", "-rf", "/"]))
            let token = m.receive(a, risk: .high)
            XCTAssertNil(token, "\(policy) 下 high 不可自動核")
            XCTAssertEqual(m.state, .awaitingApproval(a, .high))
        }
    }

    func testMediumNotAutoApprovedUnderAutoBounded() {
        var m = TakeoverSessionModel(policy: .autoBounded)
        m.begin()
        let token = m.receive(action(.keypress("cmd+s")), risk: .medium)
        XCTAssertNil(token)                                        // 只有 low 走自動核（保守）
    }

    func testAutoBoundedApprovesLowUpToCap() {
        var m = TakeoverSessionModel(policy: .autoBounded, autoBoundedCap: 2)
        m.begin()
        let t1 = m.receive(action(), risk: .low)
        XCTAssertNotNil(t1)
        m.finishExecution()
        let t2 = m.receive(action(), risk: .low)
        XCTAssertNotNil(t2)
        m.finishExecution()
    }

    func testAutoBoundedCapFallsBackToConfirm() {
        var m = TakeoverSessionModel(policy: .autoBounded, autoBoundedCap: 1)
        m.begin()
        _ = m.receive(action(), risk: .low)      // 第 1 個自動核
        m.finishExecution()
        let a2 = action()
        let t2 = m.receive(a2, risk: .low)       // 超上限 → 回人工確認
        XCTAssertNil(t2)
        XCTAssertEqual(m.state, .awaitingApproval(a2, .low))
    }

    func testSuggestOnlyApproveNeverMints() {
        var m = TakeoverSessionModel(policy: .suggestOnly)
        m.begin()
        _ = m.receive(action(), risk: .low)
        let token = m.approve()
        XCTAssertNil(token)                      // 建議模式永不執行
        XCTAssertEqual(m.state, .proposing)
    }
}
