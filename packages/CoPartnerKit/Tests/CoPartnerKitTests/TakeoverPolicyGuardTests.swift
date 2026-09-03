import XCTest
import CoPartnerCore
@testable import ActionExecutor

/// 政策降級閘門（step 53.6-C）。
///
/// 守的是一句話：**要嘛自動執行，要嘛給 UI 控制權，不能兩個都要。**
///
/// 這條規則是翻開 UI 執行能力時才浮出來的：在只有 shell 的世界裡，autoBounded
/// 從來沒有自動執行過任何東西——因為 `RiskClassifier` 讓 shell 永遠不會是 low。
/// `.click` 是 low，打破了那個巧合。
final class TakeoverPolicyGuardTests: XCTestCase {

    private func effective(_ policy: TakeoverContract.Policy,
                           _ tools: [String]) -> TakeoverContract.Policy {
        TakeoverPolicyGuard.effectivePolicy(declared: policy, allowedTools: tools)
    }

    /// 🔑 **核心規則。** autoBounded ＋ computer → 降為 confirmEach。
    func testAutoBoundedWithUIControlIsDowngraded() {
        XCTAssertEqual(effective(.autoBounded, ["computer"]), .confirmEach)
        XCTAssertEqual(effective(.autoBounded, ["bash(sandboxed)", "computer"]), .confirmEach)
    }

    /// 帶括號的寫法要認得——`SandboxPolicy` 也是這樣認的。
    /// 兩邊對「什麼算 computer」的認定不一致，會出現最糟的組合：
    /// 執行端認為給了 UI 控制權、政策閘門認為沒給。
    func testParenthesisedToolNameCounts() {
        XCTAssertTrue(TakeoverPolicyGuard.grantsUIControl(["computer(screen)"]))
        XCTAssertEqual(effective(.autoBounded, ["computer(screen)"]), .confirmEach)
    }

    /// 沒有 UI 控制權時 autoBounded 照舊——shell 永遠不是 low，所以它自動核不到東西。
    func testAutoBoundedWithoutUIControlIsUntouched() {
        XCTAssertEqual(effective(.autoBounded, ["bash(sandboxed)"]), .autoBounded)
        XCTAssertEqual(effective(.autoBounded, []), .autoBounded)
    }

    /// 另外兩種政策本來就要問人／不執行，不受影響。
    func testOtherPoliciesArePassedThrough() {
        for policy: TakeoverContract.Policy in [.confirmEach, .suggestOnly] {
            XCTAssertEqual(effective(policy, ["computer"]), policy)
            XCTAssertEqual(effective(policy, ["bash(sandboxed)"]), policy)
        }
    }

    /// **降級一定要說得出原因。** 使用者以為自己開了 autoBounded、實際卻每個動作
    /// 都被問，沒有解釋的話那看起來像 bug 而不是保護。
    func testDowngradeIsExplained() {
        let reason = TakeoverPolicyGuard.downgradeReason(declared: .autoBounded,
                                                         allowedTools: ["computer"])
        XCTAssertNotNil(reason)
        XCTAssertTrue(reason!.contains("computer"), reason!)
        XCTAssertNil(TakeoverPolicyGuard.downgradeReason(declared: .autoBounded,
                                                         allowedTools: ["bash"]))
        XCTAssertNil(TakeoverPolicyGuard.downgradeReason(declared: .confirmEach,
                                                         allowedTools: ["computer"]))
    }

    /// 接上狀態機：降級之後，**low 風險的點按也必須進 awaitingApproval**。
    /// 這條測試才是真正的驗收——前面幾條只驗了那個函式回傳什麼。
    func testDowngradedPolicyActuallyStopsAutoApproval() {
        let contract = TakeoverContract(instruction: "", policy: .autoBounded,
                                        allowedTools: ["computer"])
        let policy = TakeoverPolicyGuard.effectivePolicy(declared: contract.policy,
                                                         allowedTools: contract.allowedTools)
        var model = TakeoverSessionModel(policy: policy)
        model.begin()
        let click = ProposedAction(kind: .click(x: 10, y: 10))
        XCTAssertEqual(RiskClassifier().classify(click), .low, "點按確實是 low——這正是問題所在")
        XCTAssertNil(model.receive(click, risk: .low), "降級之後不可以自動核")
        guard case .awaitingApproval = model.state else {
            return XCTFail("應該進 awaitingApproval，實際是 \(model.state)")
        }
    }

    /// 反面對照：**不降級的話它真的會自動核**——證明這條規則擋下來的是真的東西，
    /// 而不是一個從來不會發生的情況。
    func testWithoutTheGuardAutoBoundedWouldFireClicksUnattended() {
        var model = TakeoverSessionModel(policy: .autoBounded)
        model.begin()
        XCTAssertNotNil(model.receive(ProposedAction(kind: .click(x: 10, y: 10)), risk: .low),
                        "沒有這道閘門，點按會在沒有人看的情況下直接執行")
    }
}
