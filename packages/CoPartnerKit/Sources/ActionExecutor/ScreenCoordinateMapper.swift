import CoreGraphics
// 設計：sandbox-threat-model.md R2（UI 動作不經 shell 沙箱）＋ backlog step 53.6。
//
// UI 執行端最危險的地方**不是**它會被拒絕，而是它會**成功地做錯事**：
// 座標算錯不會回傳錯誤、不會丟例外、不會留下任何異常紀錄——
// 游標只是點到了別的地方，然後那個地方剛好有一顆「刪除」。
// shell 那條線有 sbpl 兜底；這條線沒有，所以換算本身必須是可測的純值邏輯。
//
// ## 三個座標系
//
// | 座標系 | 原點 | y 方向 | 單位 |
// |---|---|---|---|
// | 模型看到的截圖 | 圖片左上 | 向下 | **像素**（而且可能被縮放過） |
// | CG 全域顯示空間（`CGEvent` 用的） | 主顯示器左上 | 向下 | **點** |
// | AppKit `NSScreen.frame` | 主螢幕左下 | 向上 | 點 |
//
// 這裡只處理前兩者。AppKit 那組刻意不碰——多一個轉換就多一次翻轉 y 的機會，
// 而翻轉錯了在單螢幕、非 Retina、視窗剛好置中時**看起來完全正常**。
//
// ## 為什麼不出現 backingScale
//
// 直覺的寫法是「像素 ÷ 2 得到點」，那正是 Retina 類 bug 的來源：2 這個數字
// 會在某些機器上是 1、外接螢幕上又是別的值，而且截圖送給模型前通常還被縮過一次
// （computer-use 建議降解析度），於是實際比例根本不是 backingScale。
//
// 這裡改成**先化成比例再乘回去**：`圖片像素 / 圖片尺寸 → 0…1 → × 顯示器點尺寸`。
// 縮放與 Retina 在比例這一步同時被約掉，不需要知道任何一個是多少。
//
// ## 為什麼越界是拒絕而不是夾邊
//
// 夾到邊界會把「模型算錯座標」變成「點在螢幕邊緣」——一個看起來成功的動作。
// 越界代表模型對畫面的理解與實際不符，那時候**任何**點擊都不該發生。

/// 一台顯示器在 CG 全域點座標中的位置與大小。
public struct DisplayGeometry: Sendable, Equatable {
    /// 該顯示器左上角在全域座標中的位置（主顯示器為 `.zero`；左邊的螢幕會是負的）。
    public let globalOriginPoints: CGPoint
    /// 該顯示器的邏輯尺寸（點，非像素）。
    public let sizePoints: CGSize

    public init(globalOriginPoints: CGPoint, sizePoints: CGSize) {
        self.globalOriginPoints = globalOriginPoints
        self.sizePoints = sizePoints
    }
}

/// 「模型實際看到的那張圖」＋「它是哪台顯示器」。
///
/// 兩者必須成對來自**同一次擷取**。拿 A 螢幕的圖配 B 螢幕的幾何，
/// 換算會安靜地給出一個合法但完全錯誤的點——`aspectMismatch` 就是為了讓
/// 這種配錯至少在長寬比明顯不同時被抓到。
public struct ScreenshotGeometry: Sendable, Equatable {
    /// 送給模型的那張圖的尺寸（像素）。**不是**顯示器的像素尺寸——圖可能被縮過。
    public let imagePixelSize: CGSize
    public let display: DisplayGeometry

    public init(imagePixelSize: CGSize, display: DisplayGeometry) {
        self.imagePixelSize = imagePixelSize
        self.display = display
    }

    /// 圖片與顯示器的長寬比差異（相對值）。等比縮放時為 0。
    ///
    /// 用相對差而不是絕對差：4:3 與 16:9 的絕對差和 16:9 與 16:10 的絕對差
    /// 差了一個數量級，用同一個絕對門檻不可能同時合理。
    public var aspectMismatch: CGFloat {
        guard imagePixelSize.height > 0, display.sizePoints.height > 0 else { return .infinity }
        let image = imagePixelSize.width / imagePixelSize.height
        let screen = display.sizePoints.width / display.sizePoints.height
        guard screen > 0 else { return .infinity }
        return abs(image - screen) / screen
    }
}

public enum CoordinateMappingError: Error, Equatable {
    /// 座標是 NaN / 無限大。來自模型的數字沒有理由信任它是有限的。
    case nonFinite
    /// 圖片或顯示器尺寸退化（≤ 0）。此時任何比例都算不出來。
    case degenerateGeometry
    /// 座標落在圖片外。**刻意不夾邊**——見檔頭。
    case outOfBounds(x: Int, y: Int, width: Int, height: Int)
    /// 圖片與顯示器長寬比對不上，兩者多半不是同一次擷取。
    case aspectMismatch(ratio: CGFloat)
}

public enum ScreenCoordinateMapper {

    /// 長寬比容忍度。等比縮放理論上是 0，但整數尺寸的捨入會帶進一點誤差
    /// （例如 2880×1800 縮成 1366×854 而不是 853.75），所以留 1%。
    /// 放寬到能容下 16:9 vs 16:10（11%）就等於沒有這道檢查了。
    public static let aspectTolerance: CGFloat = 0.01

    /// 模型給的截圖像素座標 → `CGEvent` 用的全域點座標。
    ///
    /// - Parameter point: 模型座標，原點在圖片左上、y 向下、單位是**那張圖的像素**。
    public static func globalPoint(fromModelPoint point: CGPoint,
                                   in geometry: ScreenshotGeometry) throws -> CGPoint {
        guard point.x.isFinite, point.y.isFinite else { throw CoordinateMappingError.nonFinite }
        let image = geometry.imagePixelSize
        let screen = geometry.display.sizePoints
        guard image.width > 0, image.height > 0, screen.width > 0, screen.height > 0,
              image.width.isFinite, image.height.isFinite,
              screen.width.isFinite, screen.height.isFinite else {
            throw CoordinateMappingError.degenerateGeometry
        }
        // 半開區間：寬 100 的圖，合法 x 是 0…99。x == 100 已經在圖外一個像素。
        guard point.x >= 0, point.y >= 0, point.x < image.width, point.y < image.height else {
            throw CoordinateMappingError.outOfBounds(
                x: Int(point.x.rounded()), y: Int(point.y.rounded()),
                width: Int(image.width), height: Int(image.height))
        }
        let mismatch = geometry.aspectMismatch
        guard mismatch <= aspectTolerance else {
            throw CoordinateMappingError.aspectMismatch(ratio: mismatch)
        }
        // 化成比例再乘回去——縮放與 Retina 在這一步被約掉，見檔頭。
        return CGPoint(
            x: geometry.display.globalOriginPoints.x + point.x / image.width * screen.width,
            y: geometry.display.globalOriginPoints.y + point.y / image.height * screen.height)
    }

    /// 捲動量不需要座標系換算（它是相對量），但仍要擋掉荒謬的值。
    ///
    /// 上限是**明確的政策而不是保護**：一次捲 10 萬行不會壞掉任何東西，
    /// 只是代表模型把單位搞錯了（像素當行數之類），而那時候該停下來問人。
    public static let scrollLineLimit = 500

    public static func isReasonableScroll(dx: Int, dy: Int) -> Bool {
        abs(dx) <= scrollLineLimit && abs(dy) <= scrollLineLimit
    }
}
