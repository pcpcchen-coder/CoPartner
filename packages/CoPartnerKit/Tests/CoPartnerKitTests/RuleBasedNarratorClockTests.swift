import XCTest
import CoPartnerCore
import ScriptNarrator

/// 規則式敘事器的時鐘語意（step 42 真機回歸）。
///
/// 背景：app 端的 `NarrationLadder` 現在是**長期存活的一份**（建一次用整個觀察期），
/// 因為 narrator 重建會把 prewarm 的效果丟掉。若 `RuleBasedNarrator` 在 init 就把
/// `Date()` 釘死，整場觀察產出的規則式 step 會共用同一個時間戳——
/// `L1HotBuffer` 的時間窗過濾與記憶層排序都會失準，而且症狀隱晦（step 有出來，只是時間錯）。
///
/// ⚠️ 寫法注意：`await` 不可以放進 `XCTUnwrap` 的參數裡——它收的是**非 async 的
/// autoclosure**，塞 await 進去會編譯失敗。而且 `swift build` 只編 library、
/// 測試 target 要到 `swift test` 才編，所以這種錯誤在 CI 上會偽裝成「build 成功、
/// 測試失敗」，看起來像斷言掛掉。一律先 await 到區域變數再 unwrap。
final class RuleBasedNarratorClockTests: XCTestCase {
    private let lines = ["[00:00:01.000] TYPE app=Xcode field=e text=\"hi\""]

    /// 沒注入時鐘 → 每次敘事各自取當下時間，不可共用建構時的時間戳。
    func testUninjectedClockAdvancesBetweenCalls() async throws {
        let narrator = RuleBasedNarrator()
        let firstStep = await narrator.narrate(lines)
        let first = try XCTUnwrap(firstStep)
        try await Task.sleep(for: .milliseconds(50))
        let secondStep = await narrator.narrate(lines)
        let second = try XCTUnwrap(secondStep)
        XCTAssertGreaterThan(second.startedAt, first.startedAt,
                             "同一份 narrator 長期存活時，時間戳必須跟著推進")
    }

    /// 注入固定時鐘 → 維持確定性（既有測試依賴這個行為）。
    func testInjectedClockStaysFixed() async throws {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let narrator = RuleBasedNarrator(now: t0)
        let stepA = await narrator.narrate(lines)
        let a = try XCTUnwrap(stepA)
        let stepB = await narrator.narrate(lines)
        let b = try XCTUnwrap(stepB)
        XCTAssertEqual(a.startedAt, t0)
        XCTAssertEqual(b.startedAt, t0)
    }
}
