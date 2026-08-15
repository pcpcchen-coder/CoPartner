import XCTest
import CoreGraphics
import CaptureEngine

/// 局部 OCR 裁切（§B.8）：焦點框 → 加 padding → 夾螢幕；無效焦點則略過。
/// step 29 dogfood 回歸：修復前是「截整螢幕 OCR」，混入選單列/他 app 文字且違反吞吐指標。
final class OCRCropPlannerTests: XCTestCase {
    private let w = 1920, h = 1080

    func testAddsPaddingAroundFocusFrame() {
        let crop = OCRCropPlanner.cropRect(focusFrame: CGRect(x: 500, y: 400, width: 200, height: 100),
                                           screenWidth: w, screenHeight: h, padding: 40)
        XCTAssertEqual(crop, CGRect(x: 460, y: 360, width: 280, height: 180))
    }

    func testClampsToScreenBounds() {
        // 焦點貼左上角：加 padding 會超出螢幕 → 夾回 (0,0)
        let crop = OCRCropPlanner.cropRect(focusFrame: CGRect(x: 10, y: 10, width: 100, height: 50),
                                           screenWidth: w, screenHeight: h, padding: 40)
        XCTAssertEqual(crop?.minX, 0)
        XCTAssertEqual(crop?.minY, 0)
    }

    func testNilFocusSkips() {
        XCTAssertNil(OCRCropPlanner.cropRect(focusFrame: nil, screenWidth: w, screenHeight: h))
    }

    func testDegenerateFrameSkips() {
        XCTAssertNil(OCRCropPlanner.cropRect(focusFrame: .zero, screenWidth: w, screenHeight: h))
        XCTAssertNil(OCRCropPlanner.cropRect(focusFrame: CGRect(x: 5, y: 5, width: 0, height: 0),
                                             screenWidth: w, screenHeight: h))
    }

    func testFrameFullyOffscreenSkips() {
        let crop = OCRCropPlanner.cropRect(focusFrame: CGRect(x: 5000, y: 5000, width: 100, height: 100),
                                           screenWidth: w, screenHeight: h)
        XCTAssertNil(crop)
    }

    /// M2 驗收指標：典型焦點區的像素量應遠小於全畫面（目標 ≤ ~20%）。
    func testTypicalFocusAreaIsSmallFractionOfScreen() {
        let crop = OCRCropPlanner.cropRect(focusFrame: CGRect(x: 600, y: 300, width: 500, height: 200),
                                           screenWidth: w, screenHeight: h)
        let ratio = OCRCropPlanner.areaRatio(cropRect: crop, screenWidth: w, screenHeight: h)
        XCTAssertLessThan(ratio, 0.2, "局部 OCR 應遠小於全畫面（M2 吞吐指標）")
        XCTAssertGreaterThan(ratio, 0)
    }

    func testAreaRatioZeroWhenSkipped() {
        XCTAssertEqual(OCRCropPlanner.areaRatio(cropRect: nil, screenWidth: w, screenHeight: h), 0)
    }
}
