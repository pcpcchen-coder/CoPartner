import XCTest
import CoPartnerCore
import ScriptNarrator

/// 規則式敘事器（§5 保底）：關鍵字推類別、抽 artifacts、open loop、非空永不 nil。
final class RuleBasedNarratorTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func narrator() -> RuleBasedNarrator { RuleBasedNarrator(now: t0) }

    func testEmptyLinesReturnsNil() async {
        let s = await narrator().narrate([])
        XCTAssertNil(s)
        let s2 = await narrator().narrate(["   ", ""])
        XCTAssertNil(s2)
    }

    func testCategoryInferredFromKeywords() async {
        let dbg = await narrator().narrate(["[00:00:01.000] PASTE   chars=20 preview=\"error code 1006\""])
        XCTAssertEqual(dbg?.category, "debugging")
        let search = await narrator().narrate(["[00:00:01.000] SWITCH  app=Safari win=\"Google 搜尋\""])
        XCTAssertEqual(search?.category, "searching")
        let edit = await narrator().narrate(["[00:00:01.000] TYPE    field=editor text=\"hello\""])
        XCTAssertEqual(edit?.category, "editing")
    }

    func testArtifactsExtracted() async {
        let s = await narrator().narrate([
            "[00:00:01.000] FOCUS   app=Xcode win=\"ContentView.swift\"",
            "[00:00:02.000] TYPE    field=editor text=\"see https://example.com/doc\"",
        ])
        XCTAssertEqual(s?.artifacts.contains("ContentView.swift"), true)
        XCTAssertEqual(s?.artifacts.contains("https://example.com/doc"), true)
    }

    func testOpenLoopDetected() async {
        let typing = await narrator().narrate([
            "[00:00:01.000] FOCUS  app=X win=\"a\"",
            "[00:00:02.000] TYPE   field=e text=\"hi\"",
        ])
        XCTAssertEqual(typing?.openLoop, true)
        let done = await narrator().narrate([
            "[00:00:01.000] TYPE   field=e text=\"hi\"",
            "[00:00:02.000] SWITCH app=Y win=\"b\"",
        ])
        XCTAssertEqual(done?.openLoop, false)
    }

    func testNonEmptyNeverReturnsNil() async {
        let s = await narrator().narrate(["[00:00:01.000] WATCH   video"])
        XCTAssertNotNil(s)
        XCTAssertEqual(s?.confidence ?? -1, 0.3, accuracy: 1e-9)   // 避開 optional+accuracy
    }

    func testInferredApp() async {
        let s = await narrator().narrate(["[00:00:01.000] FOCUS   app=Xcode win=\"a\""])
        XCTAssertEqual(s?.app, "Xcode")
    }

    func testNarratorUsesInjectedBackend() async {
        let sentinel = ActionStep(startedAt: t0, app: "Z", category: "c", whatHappened: "w",
                                  inferredGoal: "sentinel", confidence: 1, artifacts: [], openLoop: false)
        struct Fixed: NarrationBackend { let s: ActionStep; func narrate(_ l: [String]) async -> ActionStep? { s } }
        let narrator = Narrator(backend: Fixed(s: sentinel))
        let out = await narrator.narrate(["anything"])
        XCTAssertEqual(out?.id, sentinel.id)
    }
}
