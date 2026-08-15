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
        XCTAssertEqual(out, "上 下")   // 左上原點：y 小者在上
    }

    /// Vision 的 boundingBox 是**左下原點**（y 越大越上面）——用錯慣例摘要會上下顛倒。
    func testBottomLeftOriginReversesReadingOrder() {
        let segs = [seg("下", 0.9, y: 0.1), seg("上", 0.9, y: 0.8)]   // Vision 慣例
        XCTAssertEqual(OCRTextDigest.snippet(from: segs, origin: .bottomLeft), "上 下")
        // 同一批資料若誤用左上原點慣例 → 顛倒（這正是要避免的 bug）
        XCTAssertEqual(OCRTextDigest.snippet(from: segs, origin: .topLeft), "下 上")
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
