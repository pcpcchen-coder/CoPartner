// 🔒 step 42：真 FoundationModels（Apple Intelligence 3B）L1 敘事。
// 整檔以 #if canImport(FoundationModels) 隔離——CI 的 macos-15 runner 通常無此框架
// （macOS 26 才有），canImport 為 false 時整檔略過，不影響 CI；真機（macOS 26 + Apple
// Intelligence 開啟）才編譯與執行。真敘事品質 / availability 於 step 42 真機驗收。
#if canImport(FoundationModels)
import Foundation
import FoundationModels
import CoPartnerCore

/// FoundationModels 的結構化輸出型別（v2.1 §2）。**刻意不叫 ActionStep** 以免與
/// `CoPartnerCore.ActionStep` 撞名；narrate 後以純函式映射過去。
@available(macOS 26.0, *)
@Generable
struct GeneratedStep {
    @Guide(description: "動作類別: editing/reading/searching/debugging/configuring/communicating/watching")
    var category: String
    @Guide(description: "一句話客觀描述使用者做了什麼，繁中")
    var whatHappened: String
    @Guide(description: "推測的使用者目標，繁中；不確定就說不確定")
    var inferredGoal: String
    @Guide(description: "0-1 信心度")
    var confidence: Double
    @Guide(description: "涉及的關鍵物件：檔名/URL/錯誤碼等")
    var artifacts: [String]
    @Guide(description: "是否為未完成的進行中動作")
    var openLoop: Bool
}

@available(macOS 26.0, *)
public struct FoundationModelsNarrator: NarrationBackend {
    private let app: String
    public init(app: String = "未知") { self.app = app }

    public func narrate(_ lines: [String]) async -> ActionStep? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        let session = LanguageModelSession(instructions: """
            你是螢幕操作敘事器。輸入是一段時間內的低階事件日誌，
            輸出一個 step：客觀描述 + 謹慎的意圖推測。
            禁止臆測事件日誌沒有的資訊。只輸出結構化結果。
            """)
        let prompt = "事件日誌:\n" + lines.joined(separator: "\n")
        guard let g = try? await session.respond(to: prompt, generating: GeneratedStep.self).content else {
            return nil
        }
        return ActionStep(startedAt: Date(), app: app, category: g.category,
                          whatHappened: g.whatHappened, inferredGoal: g.inferredGoal,
                          confidence: g.confidence, artifacts: g.artifacts, openLoop: g.openLoop)
    }

    /// 降冷啟動延遲（v2.1 §2 prewarm）。
    public func warmUp() async {
        let session = LanguageModelSession()
        session.prewarm()
    }
}
#endif
