// 🔒 step 42：真 FoundationModels（Apple Intelligence 3B）L1 敘事。
// 整檔以 #if canImport(FoundationModels) 隔離——CI 的 macos-15 runner 通常無此框架
// （macOS 26 才有），canImport 為 false 時整檔略過，不影響 CI；真機（macOS 26 + Apple
// Intelligence 開啟）才編譯與執行。API 簽章已於 2026-08-16 真機校準（見 FoundationModelsProbe）。
#if canImport(FoundationModels)
import Foundation
import FoundationModels
import CoPartnerCore

/// FoundationModels 的結構化輸出型別（v2.1 §2）。**刻意不叫 ActionStep** 以免與
/// `CoPartnerCore.ActionStep` 撞名；narrate 後以純函式映射過去。
///
/// ⚠️ `@Guide` 裡的**字數上限是延遲控制手段，不只是文風要求**。
/// 端上 3B 的生成是逐 token 串行的，總延遲幾乎與輸出長度成正比——真機首測 2659ms，
/// 輸出約 80+ 個中文字；prefill 與 session 建立相比之下微不足道。要壓延遲，
/// 唯一有效的槓桿就是讓模型少講話。放寬這裡的字數 = 直接等比放大延遲。
@available(macOS 26.0, *)
@Generable
struct GeneratedStep {
    @Guide(description: "動作類別，只能是這幾個之一: editing/reading/searching/debugging/configuring/communicating/watching")
    var category: String
    @Guide(description: "使用者做了什麼，繁中，**20 字以內**，只描述事實不解釋")
    var whatHappened: String
    @Guide(description: "推測的目標，繁中，**15 字以內**；不確定就寫「不確定」")
    var inferredGoal: String
    @Guide(description: "0-1 信心度")
    var confidence: Double
    @Guide(description: "關鍵物件（檔名/URL/錯誤碼），最多 3 個；沒有就給空陣列")
    var artifacts: [String]
    @Guide(description: "是否為未完成的進行中動作")
    var openLoop: Bool
}

@available(macOS 26.0, *)
public struct FoundationModelsNarrator: NarrationBackend {
    /// 推不出 app 時的後備名稱。
    private let fallbackApp: String
    public init(app: String = "未知") { self.fallbackApp = app }

    /// 指令與 `warmUp` 共用同一份——prewarm 要預熱的就是實際會用到的那組設定。
    private static let instructions = """
        你是螢幕操作敘事器。輸入是低階事件日誌，輸出一個 step：客觀描述 + 謹慎的意圖推測。
        禁止臆測日誌沒有的資訊。**極度簡潔**：每個欄位都要壓到字數上限內，不要補充說明、
        不要舉例、不要重複日誌內容。
        用**台灣繁體中文用語**（視訊不是視頻、程式不是程序、檔案不是文件、網路不是網絡）。
        只輸出結構化結果。
        """

    public func narrate(_ lines: [String]) async -> ActionStep? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        let session = LanguageModelSession(instructions: Self.instructions)
        let prompt = "事件日誌:\n" + lines.joined(separator: "\n")
        guard let g = try? await session.respond(to: prompt, generating: GeneratedStep.self).content else {
            return nil
        }
        // app 從日誌行推導（`app=…`）而非 init 綁定：narrator 因此與「現在在哪個 app」
        // 無關，可以長期存活一份，prewarm 的效果才不會被每次重建丟掉。
        let app = RuleBasedNarrator.inferApp(lines) ?? fallbackApp
        return ActionStep(startedAt: Date(), app: app, category: g.category,
                          whatHappened: g.whatHappened, inferredGoal: g.inferredGoal,
                          confidence: g.confidence, artifacts: g.artifacts, openLoop: g.openLoop)
    }

    /// 降冷啟動延遲（v2.1 §2 prewarm）。
    /// 用與 `narrate` 相同的 instructions 建 session——預熱不同設定的 session 意義有限。
    public func warmUp() async {
        let session = LanguageModelSession(instructions: Self.instructions)
        session.prewarm()
    }
}
#endif
