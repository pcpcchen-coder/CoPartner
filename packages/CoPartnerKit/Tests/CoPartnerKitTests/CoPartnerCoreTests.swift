import XCTest
@testable import CoPartnerCore

final class CoPartnerCoreTests: XCTestCase {
    func testActionStepCodableRoundTrip() throws {
        let step = ActionStep(startedAt: Date(), app: "Xcode", category: "debugging",
            whatHappened: "撰寫 reconnectWebSocket", inferredGoal: "實作指數退避重連",
            confidence: 0.82, artifacts: ["EMSController.swift"], openLoop: true)
        let data = try JSONEncoder().encode(step)
        let decoded = try JSONDecoder().decode(ActionStep.self, from: data)
        XCTAssertEqual(decoded.app, "Xcode")
        XCTAssertTrue(decoded.openLoop)
    }
}
