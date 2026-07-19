import XCTest
import CaptureEngine

/// dHash 差異比對與變動分級（§B.2）。hash 產生端（GPU）於 step 18 真機驗。
final class TileHashDiffTests: XCTestCase {
    func testIdenticalHashesZeroDistance() {
        XCTAssertEqual(TileHashDiff.hammingDistance(0xDEAD_BEEF_CAFE_F00D, 0xDEAD_BEEF_CAFE_F00D), 0)
    }

    func testHammingDistanceKnownBitPatterns() {
        XCTAssertEqual(TileHashDiff.hammingDistance(0b0, 0b1), 1)
        XCTAssertEqual(TileHashDiff.hammingDistance(0b1010, 0b0101), 4)
        XCTAssertEqual(TileHashDiff.hammingDistance(0, .max), 64)                       // 全翻
        XCTAssertEqual(TileHashDiff.hammingDistance(1 << 63, 0), 1)                     // 最高位
        XCTAssertEqual(TileHashDiff.hammingDistance(0xFF00_0000_0000_0000, 0x00FF_0000_0000_0000), 16)
    }

    func testZeroDistanceIsNone() {
        XCTAssertEqual(TileHashDiff.classify(distance: 0), .none)
        XCTAssertEqual(TileHashDiff.classify(old: 42, new: 42), ChangeMagnitude.none)
    }

    func testSmallDistanceIsCursorResidue() {
        // 預設門檻 smallMaxBits=2：游標掃過 tile 典型翻 1–2 bit。
        XCTAssertEqual(TileHashDiff.classify(distance: 1), .small)
        XCTAssertEqual(TileHashDiff.classify(distance: 2), .small)
    }

    func testLargeDistanceIsRealChange() {
        XCTAssertEqual(TileHashDiff.classify(distance: 3), .large)
        XCTAssertEqual(TileHashDiff.classify(distance: 64), .large)
    }

    func testClassifyThresholdBoundaries() {
        let custom = ChangeThresholds(smallMaxBits: 5)
        XCTAssertEqual(TileHashDiff.classify(distance: 5, thresholds: custom), .small)   // 邊界含
        XCTAssertEqual(TileHashDiff.classify(distance: 6, thresholds: custom), .large)   // 邊界外
        // smallMaxBits=0 → 停用 small 分級：任何變動都算 large
        let strict = ChangeThresholds(smallMaxBits: 0)
        XCTAssertEqual(TileHashDiff.classify(distance: 1, thresholds: strict), .large)
        // 負值輸入被 init 夾成 0
        XCTAssertEqual(ChangeThresholds(smallMaxBits: -3).smallMaxBits, 0)
    }

    func testClassifyOldNewConvenience() {
        // 差 1 bit → small；差 4 bit → large
        XCTAssertEqual(TileHashDiff.classify(old: 0b1000, new: 0b0000), ChangeMagnitude.small)
        XCTAssertEqual(TileHashDiff.classify(old: 0b1111, new: 0b0000), ChangeMagnitude.large)
    }
}
