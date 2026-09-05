import AppKit
import ActionExecutor
import CoPartnerCore
// 🔒 真機膠水：主顯示器的幾何。CI 只保證編譯。
//
// ## 為什麼這裡只有一個函式
//
// 送給 Claude 的 `display_width_px` / `display_height_px` 決定了它回傳座標的意義；
// 而 `ScreenCoordinateMapper` 要用同一組數字才換算得回正確的位置。
// **這兩個值從兩個地方各自取，就有不一致的可能，而不一致的後果是每一次點擊都落在
// 錯的位置、且完全不會報錯**——`HandoffRequestBuilder` 的註解已經寫過同一句話。
//
// 所以宣告給雲端的尺寸與換算用的幾何由**同一個函式**產生，不給它們分岔的機會。
enum ScreenGeometryProvider {

    /// 主顯示器的截圖幾何：宣告給模型的像素尺寸 ＋ CGEvent 用的點座標。
    /// 取不到螢幕時回 nil——**不給預設值**，理由同 `HandoffRequestBuilder`。
    static func mainDisplay() -> ScreenshotGeometry? {
        // `NSScreen.screens.first` 是主顯示器（AppKit 座標原點所在），
        // `NSScreen.main` 是「目前有鍵盤焦點」的那一台——兩者可以不同。
        // 全域座標的換算基準必須用前者。
        guard let primary = NSScreen.screens.first,
              let screen = NSScreen.main ?? NSScreen.screens.first else { return nil }

        let sizePoints = screen.frame.size
        // AppKit 原點在主螢幕**左下**、y 向上；CG 全域原點在主螢幕**左上**、y 向下。
        // 翻轉只在這裡做一次，而且只做這一次——多一處翻轉就多一次翻錯的機會，
        // 而翻錯在單螢幕、視窗置中時看起來完全正常。
        let originGlobal = CGPoint(x: screen.frame.origin.x,
                                   y: primary.frame.maxY - screen.frame.maxY)
        let scale = screen.backingScaleFactor
        let native = CGSize(width: sizePoints.width * scale, height: sizePoints.height * scale)
        // ⚠️ `imagePixelSize` 是「**我們送給模型的圖有多大**」，不是螢幕原生像素。
        // 送出去的圖會被縮到 `ScreenshotScalePolicy.targetSize`，而宣告給模型的
        // `display_width_px/height_px` 與這裡的換算基準都必須用同一個數字——
        // 三者任一錯開，每個座標都會偏掉，而且不會報錯（見該型別的說明）。
        guard let target = ScreenshotScalePolicy.targetSize(nativePixels: native) else { return nil }
        return ScreenshotGeometry(
            imagePixelSize: target,
            display: DisplayGeometry(globalOriginPoints: originGlobal, sizePoints: sizePoints))
    }

    /// 給 `HandoffRequestBuilder` 用的宣告尺寸。**與送出去的圖、與換算用的幾何同源**
    /// ——三者都取自 `mainDisplay()` 的 `imagePixelSize`，沒有分岔的機會。
    static func declaredDisplayPixels() -> (width: Int, height: Int)? {
        guard let geometry = mainDisplay() else { return nil }
        return (Int(geometry.imagePixelSize.width.rounded()),
                Int(geometry.imagePixelSize.height.rounded()))
    }
}
