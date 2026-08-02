import XCTest
import CoPartnerCore
import CaptureEngine

/// AX 文字優先決策（§B.4 / §B.8），組合 CaptureThrottle。
final class TextSourcePolicyTests: XCTestCase {
    private let throttle = CaptureThrottle(hotOCRInterval: 0.5)

    func testAXTextAlwaysUsesAccessibility() {
        XCTAssertEqual(TextSourcePolicy.source(hasAXText: true, state: .warm, throttle: throttle, sinceLastOCR: 0),
                       .accessibility)
        // 即使 dynamic / cold，有 AX 文字也免 OCR
        XCTAssertEqual(TextSourcePolicy.source(hasAXText: true, state: .dynamic, throttle: throttle, sinceLastOCR: 100),
                       .accessibility)
    }

    func testNoAXTextWarmRunsOCR() {
        XCTAssertEqual(TextSourcePolicy.source(hasAXText: false, state: .warm, throttle: throttle, sinceLastOCR: 0),
                       .ocr)
    }

    func testNoAXTextColdOrDynamicSkips() {
        XCTAssertEqual(TextSourcePolicy.source(hasAXText: false, state: .cold, throttle: throttle, sinceLastOCR: 100),
                       .skip)
        XCTAssertEqual(TextSourcePolicy.source(hasAXText: false, state: .dynamic, throttle: throttle, sinceLastOCR: 100),
                       .skip)
    }

    func testNoAXTextHotThrottled() {
        XCTAssertEqual(TextSourcePolicy.source(hasAXText: false, state: .hot, throttle: throttle, sinceLastOCR: 0.3),
                       .skip)   // 太快
        XCTAssertEqual(TextSourcePolicy.source(hasAXText: false, state: .hot, throttle: throttle, sinceLastOCR: 0.6),
                       .ocr)    // 到間隔
    }
}
