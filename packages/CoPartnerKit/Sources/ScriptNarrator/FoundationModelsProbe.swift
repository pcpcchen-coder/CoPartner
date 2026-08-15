// 🔬 step 42 前置：FoundationModels API 簽章探針（只在 macOS 26 真機編譯）。
//
// 為什麼需要這個檔：`FoundationModelsNarrator` 用到 7 個從未被編譯過的 API 面，
// 而 **CI 永遠驗不到**（macos-15 runner 無 FoundationModels → canImport false → 整檔略過）。
// 一次編譯整個 narrator 會噴出互相牽連的錯誤，難判斷根因；這裡把每個 API 面**逐項隔離**
// 成獨立函式並編號，編譯錯誤會直接指向「第 N 項簽章不對」，一輪就能全部校準。
//
// 用法：在 macOS 26 的 Xcode ⌘B，把紅字連同「PROBE N」編號回報即可。
// 校準完成後本檔可刪（或留著當 API 契約的可執行文件）。
#if canImport(FoundationModels)
import Foundation
import FoundationModels

@available(macOS 26.0, *)
enum FoundationModelsProbe {

    // PROBE 1 — @Generable / @Guide 巨集是否存在、能否套用在 struct 與各型別欄位上。
    @Generable
    struct ProbeStep {
        @Guide(description: "字串欄位")
        var text: String
        @Guide(description: "數值欄位")
        var score: Double
        @Guide(description: "布林欄位")
        var flag: Bool
        @Guide(description: "陣列欄位")
        var items: [String]
    }

    // PROBE 2 — SystemLanguageModel.default 是否存在。
    static func probe2_defaultModel() -> SystemLanguageModel {
        SystemLanguageModel.default
    }

    // PROBE 3 — .availability 的型別與 case 名稱（我們假設可對 `.available` 做 pattern match）。
    static func probe3_availability() -> Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    // PROBE 4 — LanguageModelSession 的兩種建構式（有無 instructions）。
    static func probe4_init() -> (LanguageModelSession, LanguageModelSession) {
        let plain = LanguageModelSession()
        let withInstructions = LanguageModelSession(instructions: "你是測試用敘事器。")
        return (plain, withInstructions)
    }

    // PROBE 5 — prewarm()：是否為同步、無參數、非 throwing。
    static func probe5_prewarm() {
        let session = LanguageModelSession()
        session.prewarm()
    }

    // PROBE 6 — respond(to:generating:)：async/throws、泛型參數位置、回傳值是否有 .content。
    static func probe6_structuredRespond() async throws -> ProbeStep {
        let session = LanguageModelSession(instructions: "只輸出結構化結果。")
        let response = try await session.respond(to: "測試", generating: ProbeStep.self)
        return response.content
    }

    // PROBE 7 — 純文字 respond(to:)：確認純文字路徑的回傳型別（fallback 用）。
    static func probe7_textRespond() async throws -> String {
        let session = LanguageModelSession()
        let response = try await session.respond(to: "測試")
        return response.content
    }
}
#endif
