import CoreGraphics
// 設計：威脅模型 T6/I6（出境硬牆）＋ §G 縱深五層。step 58。
//
// ## 這一層為什麼是新的
//
// 在此之前 CoPartner **從來沒有送過任何畫面出去**——`focusSnapshotJPEGBase64` 一直是 nil。
// 接上真雲端 computer-use 就必須送圖（Claude 是看著截圖給座標的），而那是整個專案
// 隱私上最大的一步。
//
// 更要緊的是：`EgressGate` 原本**完全沒有看過那個欄位**。它只掃文字，然後
// `var out = envelope` 把圖原封不動帶出去。也就是說在這一層存在之前，只要有人塞一張圖
// 進 envelope，那張圖會**一路出境而不經任何檢查**——連 PIPL 硬牆都繞過去了，
// 因為硬牆掃的是文字。
//
// ## 三個規則，每一個都是「不送」而不是「遮一下再送」
//
// 圖片比文字保守，理由是**圖沒辦法事後查**：文字送錯了還看得出來送了什麼；
// 一張截圖出去之後，上面有什麼只有收到的人知道。
//
// 輸入刻意全是原始值（`Bool` / `Double` / `[CGRect]`）而不是 `CaptureBlacklist`、
// `TileGrid` 這些型別——**不讓出境層依賴擷取層**，理由同 `EgressGate` 注入 scrubber。
// 幾何那一半在 `CaptureEngine.ScreenshotRedaction`，各自有測試。
public enum ScreenshotEgressPolicy {

    public enum Decision: Sendable, Equatable {
        /// 可以送，但這些**正規化矩形**（0…1）要先塗黑。
        case send(redact: [CGRect])
        /// 不送圖。**其餘欄位照常出境**——沒有圖只是少了座標能力，不是整包拒出。
        case withhold(reason: String)
    }

    /// 遮罩比例上限。超過就整張不送。
    ///
    /// 不是為了「塗太多就看不懂」——那是次要的。主要理由是：畫面上有四分之一以上
    /// 被判定為敏感時，我們對「剩下四分之三是什麼」的信心本來就不該高。
    /// tile 遮罩是**保守偵測**（sticky、fail-closed），它大面積命中代表這個畫面
    /// 就是不該離開這台機器。
    public static let defaultMaxMaskedFraction = 0.25

    /// 決定這張截圖能不能出境。
    ///
    /// - Parameters:
    ///   - isBlacklistedApp: 最前景 app 是否命中黑名單（step 56，由呼叫端問 `CaptureBlacklist`）。
    ///   - maskedFraction: 敏感 tile 佔比（`ScreenshotRedaction.maskedFraction`）。
    ///   - redactRects: 要塗黑的正規化矩形（`ScreenshotRedaction.normalizedRects`）。
    public static func decide(isBlacklistedApp: Bool,
                              frontmostAppName: String,
                              maskedFraction: Double,
                              redactRects: [CGRect],
                              maxMaskedFraction: Double = defaultMaxMaskedFraction) -> Decision {
        // ① 黑名單 app 在最前景 → 連遮都不遮，整張不送。
        //    密碼管理器 / 銀行頁面的截圖沒有「遮一遮就可以送」這種選項。
        if isBlacklistedApp {
            return .withhold(reason: "最前景是黑名單 app（\(frontmostAppName)）")
        }
        // ② 比例算不出來（NaN）→ 不送。`maskedFraction` 在格線退化時回 1，
        //    但呼叫端可能傳進別的東西，所以這裡自己也守一次。
        guard maskedFraction.isFinite, maskedFraction >= 0 else {
            return .withhold(reason: "敏感比例算不出來")
        }
        // ③ 敏感面積過大 → 整張不送。
        if maskedFraction > maxMaskedFraction {
            return .withhold(reason: String(format: "敏感區域佔 %.0f%%，超過上限 %.0f%%",
                                            maskedFraction * 100, maxMaskedFraction * 100))
        }
        return .send(redact: redactRects)
    }
}
