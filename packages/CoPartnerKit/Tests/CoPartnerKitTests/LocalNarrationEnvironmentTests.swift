import XCTest
import ScriptNarrator

/// 平台門面（step 42）。
///
/// ⚠️ 這組測試**刻意不斷言「CI 上一定是 frameworkAbsent」**。CI 現在跑 macos-15（沒有
/// FoundationModels），但 runner image 遲早會升到 macOS 26，屆時硬編的平台預期會變成
/// 假失敗；而且那種測試驗的是「CI 跑在哪個 OS」，不是門面的邏輯。
/// 這裡改為釘住**跨平台都必須成立的不變式**——availability 與 makeBackend 不可互相矛盾。
final class LocalNarrationEnvironmentTests: XCTestCase {

    /// 核心不變式：說模型可用，就一定生得出後端；生不出後端，就不該說可用。
    /// 違反它的話，階梯會拿 `fmAvailable: true` 配 `fm: nil`，靜默跳過 FM 層——
    /// 使用者看到的是「明明開著 Apple Intelligence 卻永遠走規則式」這種難查的症狀。
    func testAvailabilityAgreesWithBackendCreation() {
        let availability = LocalNarrationEnvironment.availability
        let backend = LocalNarrationEnvironment.makeFoundationModelsBackend(app: "測試")
        if availability == .available {
            XCTAssertNotNil(backend, "宣稱可用就必須生得出後端")
        }
        if backend == nil {
            XCTAssertNotEqual(availability, .available, "生不出後端就不該宣稱可用")
        }
    }

    /// 框架不存在時絕不可能可用。
    func testFrameworkAbsentImpliesNotUsable() {
        let availability = LocalNarrationEnvironment.availability
        if availability == .frameworkAbsent {
            XCTAssertFalse(availability.canUseFoundationModels)
            XCTAssertNil(LocalNarrationEnvironment.makeFoundationModelsBackend(app: "測試"))
        }
    }

    func testCanUseFoundationModelsOnlyForAvailable() {
        XCTAssertTrue(LocalNarrationAvailability.available.canUseFoundationModels)
        XCTAssertFalse(LocalNarrationAvailability.unavailable.canUseFoundationModels)
        XCTAssertFalse(LocalNarrationAvailability.frameworkAbsent.canUseFoundationModels)
    }

    /// 三種狀態在選單上要能分辨，否則使用者無從得知為什麼沒走本地模型。
    func testDisplayTextsAreDistinctAndNonEmpty() {
        let texts = [LocalNarrationAvailability.available.displayText,
                     LocalNarrationAvailability.unavailable.displayText,
                     LocalNarrationAvailability.frameworkAbsent.displayText]
        XCTAssertEqual(Set(texts).count, 3)
        XCTAssertFalse(texts.contains { $0.isEmpty })
    }

    /// prewarm 在沒有框架的平台必須是 no-op 而非崩潰——CI 就是這條路徑。
    func testPrewarmIsSafeOnAnyPlatform() async {
        await LocalNarrationEnvironment.prewarm()
    }

    /// 門面生出的後端（若有）必須真的能跑完一次敘事，不可 throw/卡住。
    /// CI 上 backend 為 nil → 測試自然略過；真機才會實際打模型。
    func testBackendProducesStepWhenAvailable() async {
        guard let backend = LocalNarrationEnvironment.makeFoundationModelsBackend(app: "測試") else {
            return   // 此平台無框架，不適用
        }
        _ = await backend.narrate(["[00:00:01.000] TYPE field=e text=\"hi\""])
        // 回 nil 是合法的（模型不可用時階梯會下降），這裡只驗它不會爆。
    }
}
