import XCTest
import CoreGraphics
import CaptureEngine

/// Vision OCR ROI 映射（§B.8）：螢幕左上原點 → Vision 正規化左下原點。
final class OCRRegionMapperTests: XCTestCase {
    func testTopOfScreenMapsToHighY() {
        // 1000×1000 螢幕、頂部 500×100 的 rect
        let roi = OCRRegionMapper.normalizedROI(screenRect: CGRect(x: 0, y: 0, width: 500, height: 100),
                                                screenWidth: 1000, screenHeight: 1000)
        XCTAssertEqual(roi.minX, 0, accuracy: 1e-9)
        XCTAssertEqual(roi.width, 0.5, accuracy: 1e-9)
        XCTAssertEqual(roi.height, 0.1, accuracy: 1e-9)
        XCTAssertEqual(roi.minY, 0.9, accuracy: 1e-9)   // 螢幕頂 → Vision 高 y（左下原點）
    }

    func testBottomOfScreenMapsToZeroY() {
        let roi = OCRRegionMapper.normalizedROI(screenRect: CGRect(x: 0, y: 900, width: 1000, height: 100),
                                                screenWidth: 1000, screenHeight: 1000)
        XCTAssertEqual(roi.minY, 0, accuracy: 1e-9)
    }

    func testOutOfBoundsClampsTo01() {
        let roi = OCRRegionMapper.normalizedROI(screenRect: CGRect(x: -50, y: -50, width: 2000, height: 2000),
                                                screenWidth: 1000, screenHeight: 1000)
        XCTAssertEqual(roi.minX, 0, accuracy: 1e-9)
        XCTAssertEqual(roi.width, 1, accuracy: 1e-9)
        XCTAssertEqual(roi.height, 1, accuracy: 1e-9)
    }

    func testBoundingROIUnionOfTiles() {
        let grid = TileGrid(width: 256, height: 256, tileSize: 128)   // 2×2
        // (0,0)+(1,1) 外接框覆蓋整個 256×256 → 正規化全螢幕
        let roi = OCRRegionMapper.boundingROI(forTiles: [TileXY(x: 0, y: 0), TileXY(x: 1, y: 1)], grid: grid)
        XCTAssertEqual(roi?.width, 1, accuracy: 1e-9)
        XCTAssertEqual(roi?.height, 1, accuracy: 1e-9)
    }

    func testEmptyTilesReturnsNil() {
        XCTAssertNil(OCRRegionMapper.boundingROI(forTiles: [], grid: TileGrid(width: 256, height: 256)))
    }
}
