import XCTest
import CoreGraphics
import CoPartnerCore
import ActionExecutor

/// 送出去的圖有多大（step 58）。
///
/// 這個型別本身很短，但它是**三個數字必須相等**的單一來源：送給模型的圖、
/// 宣告給模型的 `display_width_px`、以及把座標換算回螢幕時假設的圖寬。
/// 三者錯開時沒有任何一處會報錯，只會讓每一個座標都偏掉。
final class ScreenshotScalePolicyTests: XCTestCase {

    func testLargeDisplayIsScaledToTheLongEdgeBudget() throws {
        let target = try XCTUnwrap(ScreenshotScalePolicy.targetSize(
            nativePixels: CGSize(width: 3024, height: 1964)))
        XCTAssertEqual(max(target.width, target.height), ScreenshotScalePolicy.maxLongEdge)
        // 等比：長寬比一變，模型看到的就不是真實畫面的形狀了。
        XCTAssertEqual(target.width / target.height, 3024.0 / 1964.0, accuracy: 0.005)
    }

    /// **不放大。** 放大不會增加任何資訊，只會多花 token。
    func testSmallDisplayIsLeftAlone() {
        let native = CGSize(width: 800, height: 600)
        XCTAssertEqual(ScreenshotScalePolicy.targetSize(nativePixels: native), native)
    }

    /// 剛好等於上限時也不動（邊界值容易寫成 `>=` 而多縮一次）。
    func testExactlyAtBudgetIsUnchanged() {
        let native = CGSize(width: ScreenshotScalePolicy.maxLongEdge, height: 720)
        XCTAssertEqual(ScreenshotScalePolicy.targetSize(nativePixels: native), native)
    }

    /// 直立螢幕：上限套在**長邊**，不是寬度。
    func testPortraitDisplayUsesTheLongEdge() throws {
        let target = try XCTUnwrap(ScreenshotScalePolicy.targetSize(
            nativePixels: CGSize(width: 1200, height: 1920)))
        XCTAssertEqual(target.height, ScreenshotScalePolicy.maxLongEdge)
        XCTAssertLessThan(target.width, target.height)
    }

    /// 極端長寬比縮下來，短邊不可以變成 0——0 寬的圖既送不出去也算不出比例。
    func testExtremeAspectRatioKeepsAtLeastOnePixel() throws {
        let target = try XCTUnwrap(ScreenshotScalePolicy.targetSize(
            nativePixels: CGSize(width: 4000, height: 1)))
        XCTAssertGreaterThanOrEqual(target.height, 1)
        XCTAssertEqual(target.width, ScreenshotScalePolicy.maxLongEdge)
    }

    /// 退化尺寸回 nil，**不給預設值**——填錯不會報錯，只會讓每個座標都偏掉。
    func testDegenerateSizesReturnNil() {
        for size in [CGSize(width: 0, height: 0), CGSize(width: 1920, height: 0),
                     CGSize(width: .nan, height: 1080), CGSize(width: -100, height: 100)] {
            XCTAssertNil(ScreenshotScalePolicy.targetSize(nativePixels: size), "\(size)")
        }
    }

    /// 🔑 **接上座標換算：縮圖之後，中心點仍然對到螢幕中心。**
    ///
    /// 這條驗的是三個數字同源的實際後果。`ScreenCoordinateMapper` 在比例空間工作，
    /// 所以只要「送出去的圖尺寸」與「宣告給模型的尺寸」是同一個值，縮放就完全被約掉。
    func testScaledImageStillMapsToTheSamePhysicalPoint() throws {
        let native = CGSize(width: 3024, height: 1964)          // Retina 原生像素
        let sizePoints = CGSize(width: 1512, height: 982)
        let target = try XCTUnwrap(ScreenshotScalePolicy.targetSize(nativePixels: native))

        let geometry = ScreenshotGeometry(
            imagePixelSize: target,
            display: DisplayGeometry(globalOriginPoints: .zero, sizePoints: sizePoints))
        let centre = try ScreenCoordinateMapper.globalPoint(
            fromModelPoint: CGPoint(x: target.width / 2, y: target.height / 2), in: geometry)

        XCTAssertEqual(centre.x, sizePoints.width / 2, accuracy: 1)
        XCTAssertEqual(centre.y, sizePoints.height / 2, accuracy: 1)
    }

    /// 反面對照：**如果宣告的尺寸沒跟著縮**（用原生像素），座標就會整個偏掉。
    /// 這正是這個型別要防的失敗，而它在畫面上只會表現成「點錯地方」。
    func testMismatchedDeclaredSizeSilentlyShiftsEveryCoordinate() throws {
        let native = CGSize(width: 3024, height: 1964)
        let sizePoints = CGSize(width: 1512, height: 982)
        let target = try XCTUnwrap(ScreenshotScalePolicy.targetSize(nativePixels: native))

        // 錯的組合：圖縮了，宣告卻還是原生像素。
        let wrong = ScreenshotGeometry(
            imagePixelSize: native,
            display: DisplayGeometry(globalOriginPoints: .zero, sizePoints: sizePoints))
        let mapped = try ScreenCoordinateMapper.globalPoint(
            fromModelPoint: CGPoint(x: target.width / 2, y: target.height / 2), in: wrong)

        XCTAssertLessThan(mapped.x, sizePoints.width / 2 - 100,
                          "宣告與實際不一致時，座標會嚴重偏左——而且不會有任何錯誤")
    }
}
