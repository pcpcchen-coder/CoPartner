import XCTest
import CoPartnerCore
import ScriptNarrator

/// 規則式敘事器的時鐘語意（step 42 真機回歸）。
///
/// 背景：app 端的 `NarrationLadder` 現在是**長期存活的一份**（建一次用整個觀察期），
/// 因為 narrator 重建會把 prewarm 的效果丟掉。若 `RuleBasedNarrator` 在 init 就把
/// `Date()` 釘死，整場觀察產出的規則式 step 會共用同一個時間戳——
/// `L1HotBuffer` 的時間窗過濾與記憶層排序都會失準，而且症狀隱晦（step 有出來，只是時間錯）。
final class RuleBasedNarratorClockTests: XCTestCase {
    private let lines = ["[00:00:01.000] TYPE app=Xcode field=e text=\"hi\""]

    /// 沒注入時鐘 → 每次敘事各自取當下時間，不可共用建構時的時間戳。
    func testUninjectedClockAdvancesBetweenCalls() async throws {
        let narrator = RuleBasedNarrator()
        let first = try XCTUnwrap(await narrator.narrate(lines))
        try await Task.sleep(for: .milliseconds(20))
        let second = try XCTUnwrap(await narrator.narrate(lines))
        XCTAssertGreaterThan(second.startedAt, first.startedAt,
                             "同一份 narrator 長期存活時，時間戳必須跟著推進")
    }

    /// 注入固定時鐘 → 維持確定性（既有測試依賴這個行為）。
    func testInjectedClockStaysFixed() async throws {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let narrator = RuleBasedNarrator(now: t0)
        let a = try XCTUnwrap(await narrator.narrate(lines))
        let b = try XCTUnwrap(await narrator.narrate(lines))
        XCTAssertEqual(a.startedAt, t0)
        XCTAssertEqual(b.startedAt, t0)
    }
}
