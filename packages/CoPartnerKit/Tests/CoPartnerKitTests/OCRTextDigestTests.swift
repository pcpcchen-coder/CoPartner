import XCTest
import CaptureEngine

/// OCR 摘要（step 29）：信心過濾、由上到下排序、截長。
final class OCRTextDigestTests: XCTestCase {
    private func seg(_ text: String, _ conf: Double, y: Double = 0) -> OCRSegment {
        OCRSegment(text: text, confidence: conf, bbox: [0, y, 0.1, 0.1])
    }

    func testFiltersLowConfidence() {
        let out = OCRTextDigest.snippet(from: [seg("keep", 0.8), seg("drop", 0.2)], minConfidence: 0.5)
        XCTAssertEqual(out, "keep")
    }

    func testOrdersTopToBottom() {
        let out = OCRTextDigest.snippet(from: [seg("下", 0.9, y: 0.8), seg("上", 0.9, y: 0.1)])
        XCTAssertEqual(out, "上 下")   // 依 bbox y 由上到下
    }

    func testTruncatesToMaxChars() {
        let long = String(repeating: "x", count: 200)
        let out = OCRTextDigest.snippet(from: [seg(long, 0.9)], maxChars: 50)
        XCTAssertEqual(out.count, 51)          // 50 + "…"
        XCTAssertTrue(out.hasSuffix("…"))
    }

    func testEmptyWhenAllBelowConfidence() {
        XCTAssertEqual(OCRTextDigest.snippet(from: [seg("x", 0.1)], minConfidence: 0.5), "")
    }

    func testEmptySegments() {
        XCTAssertEqual(OCRTextDigest.snippet(from: []), "")
    }
}
