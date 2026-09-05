import CoreGraphics
// 設計：step 58（送截圖）。原生螢幕像素 → **實際送出、同時也宣告給模型**的尺寸。
//
// ## 為什麼這必須是同一個函式
//
// 三個地方要用到同一個數字，而它們錯開的話沒有任何一處會報錯：
//
// 1. **送給模型的圖**有多大
// 2. `display_width_px` / `display_height_px` **宣告**給模型的是多大
// 3. `ScreenCoordinateMapper` 把模型回傳的座標**換算**回螢幕時，以為圖有多大
//
// 模型是看著圖數像素給座標的。圖是 1280 寬、卻宣告成 1920，Claude 會以為畫面更寬，
// 於是每一個座標都往右偏——**而畫面上只會表現成「點錯地方」**。
// `HandoffRequestBuilder` 的註解早就寫過同一句話，這裡是它的第二個實例。
//
// ## 為什麼要縮小
//
// 送原生解析度有兩個代價：token 成本（一張 1920×1080 的 base64 JPEG 動輒數十萬字元），
// 以及模型在超大圖上數像素的準確度反而下降。1280 長邊是本專案的取捨，不是 API 的限制
// ——調整它只要改這一個常數，而且三處會一起跟著動。
public enum ScreenshotScalePolicy {

    /// 長邊上限（像素）。
    public static let maxLongEdge: CGFloat = 1280

    /// 原生像素尺寸 → 要送、也要宣告的尺寸。
    ///
    /// - **不放大**：螢幕比上限小的時候原樣送。放大不會增加任何資訊，只會多花 token。
    /// - **等比**：長寬比一變，模型看到的東西就跟真實畫面不是同一個形狀了。
    /// - 退化尺寸回 nil，**不給預設值**——理由同 `HandoffRequestBuilder`：
    ///   填錯不會報錯，只會讓每一個座標都偏掉。
    public static func targetSize(nativePixels: CGSize) -> CGSize? {
        let w = nativePixels.width, h = nativePixels.height
        guard w.isFinite, h.isFinite, w >= 1, h >= 1 else { return nil }
        let longEdge = max(w, h)
        guard longEdge > maxLongEdge else { return nativePixels }   // 不放大
        let scale = maxLongEdge / longEdge
        // 至少 1 像素：極端長寬比（例如 4000×1）縮下來短邊會變成 0，
        // 而 0 寬的圖既送不出去也算不出比例。
        return CGSize(width: max(1, (w * scale).rounded()),
                      height: max(1, (h * scale).rounded()))
    }
}
