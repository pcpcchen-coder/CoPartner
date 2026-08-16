import Foundation
import CoPartnerCore
#if canImport(FoundationModels)
import FoundationModels
#endif
// 設計：v2.1 §5（fallback 階梯）的**平台門面**。
//
// 為什麼需要這層：`FoundationModelsNarrator` 整個包在 `#if canImport(FoundationModels)` 裡，
// 呼叫端（AppCoordinator）若直接提及它，就得自己也散一堆 `#if` — 條件編譯會從一個檔擴散到
// 全 app。這裡把「有沒有這個框架」「模型現在可不可用」「怎麼生後端」三件事收斂成
// **在所有平台都能編譯的同一組 API**，呼叫端一行 `#if` 都不用寫。
//
// CI（macos-15，無框架）走 `.frameworkAbsent` 分支，makeBackend 回 nil → 階梯自動降到規則式，
// 所以這層本身是 CI 可測的（見 LocalNarrationEnvironmentTests）。

/// 本地模型（Apple Intelligence 3B）此刻的可用狀態。
public enum LocalNarrationAvailability: Sendable, Equatable {
    /// 框架在、模型就緒，可以敘事。
    case available
    /// 框架在，但模型不可用——未開 Apple Intelligence / 機型不支援 / 模型仍在下載。
    ///
    /// ⚠️ 這裡**刻意不細分原因**。`.unavailable` 的關聯值與其 reason case 名稱是
    /// FoundationModelsProbe **沒有驗證過**的 API 面（探針只驗了 `if case .available`）。
    /// 剛用一輪真機 build 換到「不盲寫未驗證簽章」的教訓，不該立刻又賭一次；
    /// 要顯示原因的話，加一個 PROBE 8 驗過 case 名稱再說。
    case unavailable
    /// 這台機器/SDK 根本沒有 FoundationModels（CI 的 macos-15、Linux 開發容器、macOS 15 以下）。
    case frameworkAbsent

    /// 給選單顯示的人話。
    public var displayText: String {
        switch self {
        case .available: return "本地模型：可用（Apple Intelligence）"
        case .unavailable: return "本地模型：不可用 — 改用規則式（檢查系統設定 → Apple Intelligence）"
        case .frameworkAbsent: return "本地模型：此系統無 FoundationModels — 改用規則式"
        }
    }

    /// 階梯的 `fmAvailable` 參數。
    public var canUseFoundationModels: Bool { self == .available }
}

/// FoundationModels 的平台門面：所有 `#if canImport` 收斂在這裡。
public enum LocalNarrationEnvironment {

    /// 查詢此刻的模型可用狀態。**每次呼叫都重新查**——使用者可能在觀察途中
    /// 開/關 Apple Intelligence，runbook M4 第 4 步就是要驗這個切換不中斷。
    public static var availability: LocalNarrationAvailability {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return .available }
            return .unavailable
        } else {
            return .frameworkAbsent   // 框架在 SDK 裡，但這台機器的 OS 太舊跑不到
        }
        #else
        return .frameworkAbsent
        #endif
    }

    /// 生一個 FoundationModels 敘事後端；此平台不支援則回 nil（階梯會自動略過這層）。
    public static func makeFoundationModelsBackend(app: String) -> (any NarrationBackend)? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return FoundationModelsNarrator(app: app)
        } else {
            return nil
        }
        #else
        return nil
        #endif
    }

    /// 預熱模型權重，降冷啟動延遲（v2.1 §2 prewarm；M4 驗收標準之一）。
    /// 沒有框架時是 no-op，呼叫端不必判斷平台。
    public static func prewarm() async {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            await FoundationModelsNarrator().warmUp()
        }
        #endif
    }
}
