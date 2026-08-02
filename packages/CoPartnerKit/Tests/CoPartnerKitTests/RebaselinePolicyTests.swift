import XCTest
import CaptureEngine

/// Re-baseline 觸發（§B.7）：時間 或 覆蓋率超標即觸發，時間優先報 reason。
final class RebaselinePolicyTests: XCTestCase {
    private let policy = RebaselinePolicy(maxInterval: 30, maxCoverage: 0.6)

    func testTimeExceededTriggers() {
        XCTAssertEqual(policy.decision(sinceLastBaseline: 45, coverage: 0.0),
                       .rebaseline(reason: .timeExceeded))
    }

    func testCoverageExceededTriggers() {
        XCTAssertEqual(policy.decision(sinceLastBaseline: 1, coverage: 0.7),
                       .rebaseline(reason: .coverageExceeded))
    }

    func testNeitherKeeps() {
        XCTAssertEqual(policy.decision(sinceLastBaseline: 5, coverage: 0.1), .keep)
    }

    func testBoundaryInclusive() {
        XCTAssertEqual(policy.decision(sinceLastBaseline: 30, coverage: 0),
                       .rebaseline(reason: .timeExceeded))
        XCTAssertEqual(policy.decision(sinceLastBaseline: 0, coverage: 0.6),
                       .rebaseline(reason: .coverageExceeded))
    }

    func testTimeTakesPrecedenceReason() {
        // 兩者都超標 → 回報 timeExceeded
        XCTAssertEqual(policy.decision(sinceLastBaseline: 60, coverage: 0.9),
                       .rebaseline(reason: .timeExceeded))
    }
}
