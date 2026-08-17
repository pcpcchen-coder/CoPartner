import Foundation
// 設計：§B.4（焦點追蹤）。把「焦點觀測序列」轉成 FOCUS / SWITCH 事件。純值邏輯、可測。
//
// ⚠️ 這個檔踩過**兩次**同一類錯誤，成因不同但本質相同：拿一個會變的顯示字串當視窗身分。
//   1. M2 dogfood：誤用 AX `value`（欄位內容）——終端機每輸出一字就被判定換視窗。
//      修法：改用 windowTitle。
//   2. M5 dogfood：`windowTitle` 本身也會變——終端機把尺寸寫進標題
//      （"CoPartner — -zsh — 110×33"），拉一次視窗大小就在 0.1 秒內噴 6 行 FOCUS。
//      修法：比對身分前先剝掉易變尾巴，見 `windowIdentity`。
//   3. step 54 dogfood：AX **有時候整個讀不到標題**，回空字串。空字串被當成一個合法身分，
//      於是標題在「讀得到 / 讀不到」之間跳的時候來回噴 FOCUS：
//        SWITCH app=系統設定 win=""
//        FOCUS  app=系統設定 win="隱私權與安全性"   ← "" → 有標題
//        FOCUS  app=系統設定 win=""                ← 有標題 → ""
//      修法：**空標題代表「沒有資訊」，不是「新視窗」**，見 `isUnknownTitle`。
//
// 教訓：**視窗標題是給人看的顯示字串，不是身分。** 終端機把尺寸寫進去、編輯器把髒標記
// 寫進去、瀏覽器把未讀數寫進去、播放器把時間碼寫進去，而且它隨時可能整個讀不到。
//
// 曾考慮加「同 app 內 FOCUS 最小間隔」的時間節流當通用後備，**刻意不採用**：
// 它會靜默吃掉真實的快速切換，而漏記的事件是看不見的；噪音至少看得見、下次 dogfood
// 就能發現並補一條正規化樣式。寧可留可見的噪音，也不要不可見的遺漏。
// （同樣理由，這也是為什麼 `volatilePatterns` 保守偏留。）

/// 追蹤 app / 視窗焦點變化：換 app → SWITCH，同 app 換視窗 → FOCUS，無變化 → nil。
/// 這是「操作時間機器」骨架最乾淨的訊號來源（不需重建打字內容）。
public struct FocusChangeTracker: Sendable {
    private var lastApp: String?
    private var lastWindowIdentity: String?
    public init() {}

    /// 餵入一次焦點觀測，回傳應記錄的事件；無變化回 nil。
    /// 事件裡帶的是**原始標題**（給人看），比對身分用的是正規化後的值。
    ///
    /// 核心規則：**只有「已知 → 另一個已知」才算換視窗。**
    /// 任何一端是未知（AX 讀不到標題）都只更新狀態、不發事件——
    /// 「我不知道現在是哪個視窗」跟「換到了另一個視窗」是兩件完全不同的事，
    /// 把前者當成後者就是 step 54 那串來回噴的 FOCUS。
    public mutating func event(app: String, window: String) -> L0Event? {
        // 未知標題不參與比對，也**不覆蓋**已知的身分——否則下次標題讀回來時
        // 又會被判成「換視窗」，一來一回就是兩筆假 FOCUS。
        let identity: String? = Self.isUnknownTitle(window) ? nil : Self.windowIdentity(window)

        if app != lastApp {
            lastApp = app
            lastWindowIdentity = identity     // 換 app 時一律重設基準（未知就是 nil）
            return .switchApp(app: app, window: window)
        }
        guard let identity else { return nil }              // 讀不到 → 沿用舊身分，不發事件
        let previous = lastWindowIdentity
        lastWindowIdentity = identity
        guard let previous else { return nil }              // 未知 → 已知：只是補上資訊，不是換視窗
        return previous == identity ? nil : .focus(app: app, window: window)
    }

    /// 標題等於「沒有資訊」——AX 讀不到時回空字串（某些 Electron / 全螢幕 app 常態如此）。
    ///
    /// 判斷用**原始標題**而非正規化後的值：正規化把標題剝光時會退回原值（見 `windowIdentity`），
    /// 那種情況是「標題只剩易變樣式」，不是「讀不到標題」，兩者不該混為一談。
    public static func isUnknownTitle(_ title: String) -> Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 視窗標題 → 可用來比對的身分。剝掉已知會自行變動的部分。
    ///
    /// **保守偏留**：剝過頭會讓兩個真的不同的視窗被當成同一個（漏記 FOCUS），
    /// 那比留著噪音更糟——噪音看得見，漏記看不見。所以只處理有把握的樣式。
    public static func windowIdentity(_ title: String) -> String {
        var s = title
        for pattern in volatilePatterns {
            s = pattern.stringByReplacingMatches(
                in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
        }
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        // 全部被剝光代表樣式太貪心——退回原標題，寧可有噪音也不要把不同視窗混成一個。
        return trimmed.isEmpty ? title : trimmed
    }

    /// 已知的易變樣式。清單只增不減——每次 dogfood 發現新的就補一筆。
    private static let volatilePatterns: [NSRegularExpression] = {
        let sources = [
            // 終端機尺寸："… — 110×33" / "… - 110x33"（em dash / en dash / 連字號，× 或 x）
            #"\s*[—–-]\s*\d+\s*[×x]\s*\d+\s*$"#,
            // 開頭的未讀數 / 進度："(3) " / "(45%) "
            #"^\(\d+%?\)\s*"#,
            // 編輯器髒標記："• " 開頭或 " •" 結尾
            #"^[•*]\s*"#,
            #"\s*[•*]$"#,
        ]
        return sources.compactMap { try? NSRegularExpression(pattern: $0) }
    }()
}
