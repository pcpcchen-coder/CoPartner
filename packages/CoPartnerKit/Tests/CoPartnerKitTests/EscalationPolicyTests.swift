import XCTest
import CoPartnerCore
import CloudRouter

/// 分層推理升級策略（ADR-0007 / §E.1）：小範圍辨識留本地、大變動才送雲端。
final class EscalationPolicyTests: XCTestCase {
    func testSmallLocalChangeStaysLocal() {
        var policy = EscalationPolicy()
        let tier = policy.decide(RoutingSignal(dirtyAreaRatio: 0.02, attentionEnergy: 0.3))
        XCTAssertLessThan(tier, .cloud)   // 小範圍變動 → 本地處理
    }

    func testBigChangeEscalatesToCloud() {
        var policy = EscalationPolicy()
        let tier = policy.decide(RoutingSignal(dirtyAreaRatio: 0.6))
        XCTAssertEqual(tier, .cloud)      // 大面積變動 → 往雲端送
    }

    func testLowLocalConfidenceEscalates() {
        var policy = EscalationPolicy()
        let tier = policy.decide(RoutingSignal(dirtyAreaRatio: 0.1, localConfidence: 0.2))
        XCTAssertEqual(tier, .cloud)      // 本地沒把握 → 升級
    }

    func testSensitiveNeverGoesToCloud() {
        var policy = EscalationPolicy()
        let tier = policy.decide(RoutingSignal(dirtyAreaRatio: 0.9, attentionEnergy: 1.0,
                                               localConfidence: 0.1, crossWindowTask: true,
                                               containsSensitive: true))
        XCTAssertLessThan(tier, .cloud)   // 敏感內容即使大變動也不出境（ADR-0005）
    }

    func testCooldownPreventsCloudThrash() {
        var policy = EscalationPolicy(cloudCooldown: 4)
        let t0 = Date()
        let first = policy.decide(RoutingSignal(dirtyAreaRatio: 0.6), now: t0)
        XCTAssertEqual(first, .cloud)
        // 冷卻窗內的第二次大變動不再升級，改用本地頂著
        let again = policy.decide(RoutingSignal(dirtyAreaRatio: 0.6), now: t0.addingTimeInterval(1))
        XCTAssertLessThan(again, .cloud)
        // 過了冷卻窗 → 可再次升級
        let later = policy.decide(RoutingSignal(dirtyAreaRatio: 0.6), now: t0.addingTimeInterval(5))
        XCTAssertEqual(later, .cloud)
    }
}
