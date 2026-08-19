import XCTest
import ActionExecutor

/// step 53.2：「沒有驗證就不可以有執行能力」這條不變式（威脅模型 T7）。
///
/// 這組測試守的是一個**時間上的陷阱**：開發時驗不了呼叫者 → 先放行 → 之後接上真執行
/// → 忘了把放行拿掉。終點是「本機任何程序都能叫 CoPartner 執行指令」。
///
/// 所以這裡釘住的不是「現在的行為對不對」，而是「第 ④ 段翻開執行能力的那一刻，
/// 未驗證的連線會**自動**開始被拒」——不依賴任何人記得回來改。
final class CallerVerificationTests: XCTestCase {

    private let unavailable = CallerVerification.Mode.unavailable(reason: "此組建無 Team ID")
    private let enforced = CallerVerification.Mode.enforced(requirement: #"identifier "x" and anchor apple generic"#)

    /// **最重要的一條**：驗不了 + 有執行能力 → 必須拒絕。
    func testUnverifiedCallerIsRefusedOnceServiceCanExecute() {
        let decision = CallerVerification.decide(mode: unavailable, serviceCanExecute: true)
        guard case .refuse = decision else {
            return XCTFail("驗不了呼叫者又能執行 → 必須拒絕，實際：\(decision)")
        }
    }

    /// 驗不了但 service 什麼都不會做 → 放行是安全的。
    /// 這正是第 ①②③ 段「先讓 endpoint 無害、再讓它有能力」所依賴的前提。
    func testUnverifiedCallerAcceptedWhileServiceIsInert() {
        XCTAssertEqual(CallerVerification.decide(mode: unavailable, serviceCanExecute: false), .accept)
    }

    /// requirement 已交給系統強制 → 能走到決策點就代表呼叫者符合，一律接受。
    func testEnforcedRequirementAlwaysAccepts() {
        XCTAssertEqual(CallerVerification.decide(mode: enforced, serviceCanExecute: true), .accept)
        XCTAssertEqual(CallerVerification.decide(mode: enforced, serviceCanExecute: false), .accept)
    }

    /// 窮舉四種組合，唯一不接受的必須是「驗不了 ×  能執行」。
    /// 寫成窮舉是因為這條不變式的價值就在於**沒有例外**。
    func testOnlyUnverifiedAndExecutableIsRefused() {
        var refused: [(String, Bool)] = []
        for (label, mode) in [("enforced", enforced), ("unavailable", unavailable)] {
            for canExecute in [true, false] {
                if case .refuse = CallerVerification.decide(mode: mode, serviceCanExecute: canExecute) {
                    refused.append((label, canExecute))
                }
            }
        }
        XCTAssertEqual(refused.count, 1)
        XCTAssertEqual(refused.first?.0, "unavailable")
        XCTAssertEqual(refused.first?.1, true)
    }

    /// 拒絕理由要說得出「為什麼」——自檢報告與 Console 都靠它判斷該修什麼。
    func testRefusalCarriesActionableReason() {
        guard case let .refuse(reason) =
                CallerVerification.decide(mode: .unavailable(reason: "未簽章"), serviceCanExecute: true) else {
            return XCTFail("應拒絕")
        }
        XCTAssertTrue(reason.contains("未簽章"), "理由要帶上驗不了的原因：\(reason)")
    }

    // MARK: - 對稱規則：主 app 這一側要不要送出去

    /// **最重要的一條**：驗不了 service 身分時，真動作不可送出。
    ///
    /// 少了這條，兩側就不對稱——service 端擋住「不明的呼叫者」，主 app 卻會把真動作
    /// 送給一個從未驗證過身分的 service。今天無害（service 不執行任何東西），
    /// 第 ④ 段一翻開執行能力就是「對身分不明的對象下指令」。
    func testRealActionIsNotSentToAnUnverifiableService() {
        guard case .refuse = CallerVerification.decideOutbound(mode: unavailable, isRealAction: true) else {
            return XCTFail("驗不了身分就不該送真動作")
        }
    }

    /// 自檢不受此限：送的是 `.selfTest`，協定上就不是一個動作。
    /// 診斷能力不該被安全規則鎖死，否則驗不出問題時連怎麼壞的都看不到。
    func testSelfTestMayProceedWithoutVerification() {
        XCTAssertEqual(CallerVerification.decideOutbound(mode: unavailable, isRealAction: false), .accept)
    }

    func testVerifiedServiceAcceptsBothKinds() {
        XCTAssertEqual(CallerVerification.decideOutbound(mode: enforced, isRealAction: true), .accept)
        XCTAssertEqual(CallerVerification.decideOutbound(mode: enforced, isRealAction: false), .accept)
    }

    /// 兩條規則要**同形**：唯一被拒的組合都是「驗不了 × 動真格」。
    /// 寫成對照是為了讓將來改動其中一邊時，另一邊的不對稱會立刻現形。
    func testInboundAndOutboundRulesAreSymmetric() {
        let inboundRefused = isRefused(CallerVerification.decide(mode: unavailable, serviceCanExecute: true))
        let outboundRefused = isRefused(CallerVerification.decideOutbound(mode: unavailable, isRealAction: true))
        XCTAssertTrue(inboundRefused && outboundRefused, "兩側在「驗不了 × 動真格」都必須拒絕")

        let inboundInert = isRefused(CallerVerification.decide(mode: unavailable, serviceCanExecute: false))
        let outboundInert = isRefused(CallerVerification.decideOutbound(mode: unavailable, isRealAction: false))
        XCTAssertFalse(inboundInert || outboundInert, "兩側在「驗不了 × 不動真格」都必須放行")
    }

    private func isRefused(_ decision: CallerVerification.Decision) -> Bool {
        if case .refuse = decision { return true }
        return false
    }

    func testDescribeIsHumanReadable() {
        XCTAssertTrue(CallerVerification.describe(enforced).hasPrefix("已啟用"))
        XCTAssertTrue(CallerVerification.describe(unavailable).hasPrefix("未啟用"))
    }
}
