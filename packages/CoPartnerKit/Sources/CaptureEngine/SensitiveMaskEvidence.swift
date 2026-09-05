import Foundation
import CoreGraphics
// 設計：威脅模型 T6/I6（出境硬牆）。step 61。

/// 判斷「這次的焦點讀數，能不能拿來當作『畫面上有沒有密碼欄』的證據」。
///
/// ## 為什麼需要這一層
///
/// 敏感遮罩是用**焦點元件**算出來的：焦點是密碼欄就把它的矩形塗黑，否則遮罩是空的。
/// 於是 `maskedFraction == 0` 有兩個完全不同的來源：
///
/// - 我們看清楚了，畫面上沒有密碼欄；
/// - 我們**根本沒看到控制項**，所以什麼都沒偵測到。
///
/// 前者可以送圖，後者不行——但在此之前這兩件事在資料上長得一模一樣，
/// 政策看到的都是 `0.0`，於是**第二種情況會一路放行**。
///
/// 真機第一次乾跑就是第二種：報告寫「敏感 tile：0／135（0.0%）」，政策判「可送」，
/// 而畫面上是一個沒有被塗黑的登入頁。fail-open 發生在唯一重要的那個位置上。
///
/// ## 三種「不算證據」
///
/// 1. **格線沒建起來** — 連座標空間都沒有，遮罩不可能有內容。
/// 2. **AX 讀不到焦點** — 沒有輔助使用權限，或該 app 不吐 AX。
/// 3. **讀到的不是最前景 app 的控制項** — 兩種子情況：
///    - 焦點是**容器**（`AXWindow` / `AXWebArea` / `AXGroup`…）而不是控制項。
///      這代表那個 app 沒有把內部元件攤開；瀏覽器預設就是這樣，整個網頁在 AX 上
///      是一個不透明的節點，裡面的密碼欄**永遠不會**以 `AXSecureTextField` 出現。
///    - 焦點的擁有者**不是**最前景 app。那我們量的是另一個視窗，
///      跟使用者正在看的畫面無關（例如焦點還留在自己的面板上）。
///
/// ## 刻意的設計
///
/// 回傳**所有**成立的理由而不是第一個。真機那次同時命中了「焦點是容器」與
/// 「擁有者對不上」，只講一個會讓下一輪修錯地方。
public enum SensitiveMaskEvidence {

    /// 這些 role 是**容器**，不是控制項。焦點停在容器上等於「我們沒看到裡面有什麼」。
    ///
    /// 寧可列多也不列少：多列一個的代價是「本來可以送的圖不送」，
    /// 少列一個的代價是「看不見的密碼欄被當成不存在」。兩邊不對等。
    public static let containerRoles: Set<String> = [
        "AXWindow", "AXApplication", "AXUnknown", "AXWebArea",
        "AXGroup", "AXScrollArea", "AXSplitGroup", "AXLayoutArea",
    ]

    /// 不能當證據的理由；空陣列 = 這次讀數可用。
    ///
    /// - Parameters:
    ///   - focused: 這次讀到的焦點元件（`nil` = AX 沒回傳）。
    ///   - frontmostPID: 最前景 app 的 pid（`nil` = 問不到，視為對不上帳）。
    ///   - gridTileCount: 遮罩格線的 tile 總數（`cols * rows`）。
    public static func unusableReasons(focused: AXFocusedElement?,
                                       frontmostPID: Int32?,
                                       gridTileCount: Int) -> [String] {
        var reasons: [String] = []
        if gridTileCount <= 0 {
            reasons.append("遮罩格線建不起來（讀不到主顯示器）")
        }
        guard let focused else {
            reasons.append("AX 讀不到焦點元件（沒有輔助使用權限，或最前景 app 不吐 AX）")
            return reasons
        }
        if containerRoles.contains(focused.role) {
            reasons.append("焦點是容器 \(focused.role)"
                + (focused.subrole.map { "／\($0)" } ?? "")
                + " 而不是控制項——這個 app 沒把內部元件攤開，看不到裡面有沒有密碼欄")
        }
        switch (focused.ownerPID, frontmostPID) {
        case (nil, _):
            reasons.append("讀不到焦點的擁有者，無法跟最前景 app 對帳")
        case (_, nil):
            reasons.append("問不到最前景 app 的 pid，無法跟焦點對帳")
        case let (owner?, front?) where owner != front:
            reasons.append("焦點屬於 pid \(owner)，最前景是 pid \(front)——量到的不是使用者正在看的視窗")
        default:
            break
        }
        return reasons
    }
}
