import XCTest
import CoreGraphics
@testable import ActionExecutor

/// step 53.6-A：UI 執行端的座標換算。
///
/// 這一層的失敗模式與其他層都不同——**它不會報錯，它會成功地點錯地方**。
/// 所以測試的重點不是「有沒有丟例外」，而是「算出來的數字對不對」，
/// 以及「該拒絕的有沒有真的拒絕（而不是夾到邊界然後照點）」。
final class ScreenCoordinateMapperTests: XCTestCase {

    // 這兩個 case 帶關聯值，比對時只關心是哪一種、不關心裡面的數字。
    // 先 `as?` 成具體型別再 switch——把 `Error` 存在型別直接丟給 case pattern
    // 是我不確定編不編得過的寫法，而測試檔的編譯錯誤在 `swift build` 階段看不到。
    private static func isOutOfBounds(_ error: Error) -> Bool {
        guard let mapped = error as? CoordinateMappingError else { return false }
        switch mapped {
        case .outOfBounds: return true
        default: return false
        }
    }
    private static func isAspectMismatch(_ error: Error) -> Bool {
        guard let mapped = error as? CoordinateMappingError else { return false }
        switch mapped {
        case .aspectMismatch: return true
        default: return false
        }
    }

    /// 主顯示器 1512×982 點、Retina、截圖被縮成 1512×982 以外的尺寸。
    private func geometry(image: CGSize,
                          origin: CGPoint = .zero,
                          screen: CGSize = CGSize(width: 1512, height: 982)) -> ScreenshotGeometry {
        ScreenshotGeometry(imagePixelSize: image,
                           display: DisplayGeometry(globalOriginPoints: origin, sizePoints: screen))
    }

    // MARK: - 基本換算

    func testTopLeftMapsToDisplayOrigin() throws {
        let g = geometry(image: CGSize(width: 3024, height: 1964))
        let p = try ScreenCoordinateMapper.globalPoint(fromModelPoint: .zero, in: g)
        XCTAssertEqual(p.x, 0, accuracy: 0.0001)
        XCTAssertEqual(p.y, 0, accuracy: 0.0001)
    }

    /// **Retina 不該出現在算式裡。** 同一個相對位置，不論截圖是 1× 還是 2×
    /// 還是被縮成任意尺寸，都要對應到同一個點。
    func testScaleCancelsOut() throws {
        let sizes = [CGSize(width: 1512, height: 982),      // 1×
                     CGSize(width: 3024, height: 1964),     // 2×（Retina 原生）
                     CGSize(width: 1366, height: 887)]      // 送給模型前又縮過一次
        for size in sizes {
            let g = geometry(image: size)
            // 正中央
            let p = try ScreenCoordinateMapper.globalPoint(
                fromModelPoint: CGPoint(x: size.width / 2, y: size.height / 2), in: g)
            XCTAssertEqual(p.x, 756, accuracy: 0.5, "\(size) 的中央應該都落在同一點")
            XCTAssertEqual(p.y, 491, accuracy: 0.5, "\(size) 的中央應該都落在同一點")
        }
    }

    /// 第二台螢幕在主螢幕左邊 → 全域原點是**負的**。
    /// 忽略原點的實作在單螢幕上完全正常，接上第二台螢幕才開始點錯地方。
    func testSecondaryDisplayOriginIsApplied() throws {
        let g = geometry(image: CGSize(width: 1920, height: 1080),
                         origin: CGPoint(x: -1920, y: -120),
                         screen: CGSize(width: 1920, height: 1080))
        let p = try ScreenCoordinateMapper.globalPoint(
            fromModelPoint: CGPoint(x: 100, y: 200), in: g)
        XCTAssertEqual(p.x, -1820, accuracy: 0.0001)
        XCTAssertEqual(p.y, 80, accuracy: 0.0001)
    }

    /// y 向下。翻轉錯的話，畫面上半部的東西會點到下半部——
    /// 而在正中央附近、或版面上下對稱時，看起來會像是「有時候會中」。
    func testYGrowsDownward() throws {
        let g = geometry(image: CGSize(width: 1512, height: 982))
        let top = try ScreenCoordinateMapper.globalPoint(
            fromModelPoint: CGPoint(x: 10, y: 10), in: g)
        let bottom = try ScreenCoordinateMapper.globalPoint(
            fromModelPoint: CGPoint(x: 10, y: 900), in: g)
        XCTAssertLessThan(top.y, bottom.y)
    }

    // MARK: - 拒絕路徑（比正向更重要）

    /// 越界**不夾邊**。夾邊會把「模型算錯」變成「點在螢幕邊緣」——一個看起來成功的動作。
    func testOutOfBoundsIsRejectedNotClamped() {
        let g = geometry(image: CGSize(width: 1512, height: 982))
        for point in [CGPoint(x: -1, y: 10), CGPoint(x: 10, y: -1),
                      CGPoint(x: 1512, y: 10), CGPoint(x: 10, y: 982),
                      CGPoint(x: 99999, y: 99999)] {
            XCTAssertThrowsError(
                try ScreenCoordinateMapper.globalPoint(fromModelPoint: point, in: g),
                "\(point) 應該被拒絕") { error in
                XCTAssertTrue(Self.isOutOfBounds(error),
                              "\(point) 應該是 outOfBounds，實際是 \(error)")
            }
        }
    }

    /// 半開區間：寬 1512 的圖，合法 x 是 0…1511。
    func testLastPixelIsInsideAndWidthIsOutside() throws {
        let g = geometry(image: CGSize(width: 1512, height: 982))
        XCTAssertNoThrow(try ScreenCoordinateMapper.globalPoint(
            fromModelPoint: CGPoint(x: 1511, y: 981), in: g))
        XCTAssertThrowsError(try ScreenCoordinateMapper.globalPoint(
            fromModelPoint: CGPoint(x: 1512, y: 981), in: g))
    }

    func testNonFiniteIsRejected() {
        let g = geometry(image: CGSize(width: 1512, height: 982))
        for point in [CGPoint(x: .nan, y: 0), CGPoint(x: 0, y: .infinity)] {
            XCTAssertThrowsError(
                try ScreenCoordinateMapper.globalPoint(fromModelPoint: point, in: g)) { error in
                XCTAssertEqual(error as? CoordinateMappingError, .nonFinite)
            }
        }
    }

    func testDegenerateGeometryIsRejected() {
        let zeroImage = geometry(image: .zero)
        XCTAssertThrowsError(try ScreenCoordinateMapper.globalPoint(
            fromModelPoint: .zero, in: zeroImage)) { error in
            XCTAssertEqual(error as? CoordinateMappingError, .degenerateGeometry)
        }
        let zeroScreen = geometry(image: CGSize(width: 100, height: 100), screen: .zero)
        XCTAssertThrowsError(try ScreenCoordinateMapper.globalPoint(
            fromModelPoint: .zero, in: zeroScreen)) { error in
            XCTAssertEqual(error as? CoordinateMappingError, .degenerateGeometry)
        }
    }

    /// 拿 A 螢幕的圖配 B 螢幕的幾何：換算會給出一個**合法但完全錯誤**的點。
    /// 長寬比對不上是唯一能在純值層抓到這件事的訊號。
    func testAspectMismatchIsRejected() {
        // 16:9 的圖配 3:2 的螢幕
        let g = geometry(image: CGSize(width: 1920, height: 1080),
                         screen: CGSize(width: 1512, height: 982))
        XCTAssertThrowsError(try ScreenCoordinateMapper.globalPoint(
            fromModelPoint: CGPoint(x: 10, y: 10), in: g)) { error in
            XCTAssertTrue(Self.isAspectMismatch(error), "應該是 aspectMismatch，實際是 \(error)")
        }
    }

    /// 但**整數捨入不該被誤判**：等比縮放很少除得盡。
    func testRoundingDoesNotTripAspectCheck() {
        let g = geometry(image: CGSize(width: 1366, height: 887))   // 1512×982 縮成整數
        XCTAssertLessThanOrEqual(g.aspectMismatch, ScreenCoordinateMapper.aspectTolerance)
        XCTAssertNoThrow(try ScreenCoordinateMapper.globalPoint(
            fromModelPoint: CGPoint(x: 683, y: 443), in: g))
    }

    // MARK: - 捲動

    func testScrollLimits() {
        XCTAssertTrue(ScreenCoordinateMapper.isReasonableScroll(dx: 0, dy: 3))
        XCTAssertTrue(ScreenCoordinateMapper.isReasonableScroll(dx: -500, dy: 500))
        XCTAssertFalse(ScreenCoordinateMapper.isReasonableScroll(dx: 0, dy: 100_000))
        XCTAssertFalse(ScreenCoordinateMapper.isReasonableScroll(dx: -501, dy: 0))
    }
}
