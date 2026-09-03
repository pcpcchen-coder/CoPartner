import Foundation
import CoPartnerCore
// 設計：sandbox-threat-model.md I2/R2 ＋ backlog step 53.6-C。
//
// ## 這個型別存在的理由，是翻開 UI 執行能力時才浮出來的
//
// `TakeoverSessionModel` 在 `.autoBounded` 政策下會**自動核准 low 風險的動作**
// （上限 5 個），不經 HUD、不問人。在只有 shell 的世界裡這是安全的：
// `RiskClassifier` 讓 shell **永遠不會是 low**（最低 medium），所以 autoBounded
// 實際上從來沒有自動執行過任何會動到系統的東西。
//
// UI 動作打破了那個巧合：**`.click` 是 low**。而一次點擊就可能按到「刪除」——
// 而且我們在事前無法知道那顆按鈕是什麼（AX 探測只在乾跑時做，真提議來自雲端、
// 座標由模型給）。shell 那一側還有 sbpl 沙箱兜底；UI 這一側**什麼都沒有**。
//
// 所以規則是：**要嘛自動執行，要嘛給 UI 控制權，不能兩個都要。**
//
// 這條規則刻意寫成純值函式而不是散在協調層的一個 if：政策降級如果只發生在某條
// 程式路徑上，日後多一條路徑就會漏掉，而漏掉的表現是「有時候不會問你」。
public enum TakeoverPolicyGuard {

    /// contract 宣告的政策 → **實際採用**的政策。
    ///
    /// 目前只有一條降級規則，但回傳型別刻意設計成「宣告 → 實際」的映射而不是
    /// 一個 bool：日後若有第二條規則，呼叫端不需要改。
    public static func effectivePolicy(declared: TakeoverContract.Policy,
                                       allowedTools: [String]) -> TakeoverContract.Policy {
        guard declared == .autoBounded, grantsUIControl(allowedTools) else { return declared }
        return .confirmEach
    }

    /// 這次 contract 有沒有給 UI 控制權（computer tool）。
    ///
    /// 與 `SandboxPolicy.has` 同樣接受 `computer(...)` 這種帶括號的寫法——
    /// 兩邊對「什麼算 computer」的認定必須一致，不然會出現
    /// 「執行端認為給了、政策閘門認為沒給」這種最糟的組合。
    public static func grantsUIControl(_ allowedTools: [String]) -> Bool {
        allowedTools.contains { $0 == "computer" || $0.hasPrefix("computer(") }
    }

    /// 政策被降級時給人看的說明。**降級必須說出來**——
    /// 使用者以為自己開了 autoBounded、實際卻每個動作都被問，
    /// 若沒有解釋，那看起來像 bug 而不是保護。
    public static func downgradeReason(declared: TakeoverContract.Policy,
                                       allowedTools: [String]) -> String? {
        guard effectivePolicy(declared: declared, allowedTools: allowedTools) != declared else {
            return nil
        }
        return "contract 要求 autoBounded，但同時要了 UI 控制權（computer）"
            + "——一次點擊就可能按到「刪除」，而 UI 動作沒有沙箱兜底，因此降為逐一確認"
    }
}
