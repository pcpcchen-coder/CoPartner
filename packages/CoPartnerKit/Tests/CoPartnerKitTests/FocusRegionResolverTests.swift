import XCTest
import CoreGraphics
import CaptureEngine

/// 焦點重點區計算與打字錨定（§B.4）。真 AX 讀取行為於 step 10 真機驗收。
final class FocusRegionResolverTests: XCTestCase {
    private let resolver = FocusRegionResolver()   // 預設最小區 600×400

    func testNoFocusedElementReturnsNil() {
        XCTAssertNil(resolver.region(for: nil))
    }

    func testSmallElementExpandsToMinimumSizeCenteredOnIt() {
        // 20×20 的小 text field，中心在 (100,100)
        let el = AXFocusedElement(role: "AXTextField", frame: CGRect(x: 90, y: 90, width: 20, height: 20))
        guard let region = resolver.region(for: el) else { return XCTFail("有焦點應算出區域") }
        XCTAssertEqual(region.rect.width, 600)
        XCTAssertEqual(region.rect.height, 400)
        XCTAssertEqual(region.rect.midX, 100, accuracy: 1e-9)   // 仍置中於元件
        XCTAssertEqual(region.rect.midY, 100, accuracy: 1e-9)
    }

    func testLargeElementKeepsItsOwnSize() {
        let el = AXFocusedElement(role: "AXTextArea", frame: CGRect(x: 0, y: 0, width: 1200, height: 800))
        let region = resolver.region(for: el)
        XCTAssertEqual(region?.rect.width, 1200)
        XCTAssertEqual(region?.rect.height, 800)
    }

    func testHasAXTextReflectsValuePresence() {
        let withText = AXFocusedElement(role: "AXTextArea", frame: .zero, value: "func foo() {")
        let empty = AXFocusedElement(role: "AXTextArea", frame: .zero, value: "")
        let none = AXFocusedElement(role: "AXButton", frame: .zero, value: nil)
        XCTAssertEqual(resolver.region(for: withText)?.hasAXText, true)
        XCTAssertEqual(resolver.region(for: empty)?.hasAXText, false)
        XCTAssertEqual(resolver.region(for: none)?.hasAXText, false)
    }

    func testTypingAnchorsToFocusedElementNotCursor() {
        // 元件 (200,300,400,200) → 中心 (400,400)；游標在遠處
        let el = AXFocusedElement(role: "AXTextArea", frame: CGRect(x: 200, y: 300, width: 400, height: 200))
        let center = resolver.attentionCenter(mouseLocation: CGPoint(x: 10, y: 10),
                                              focusedElement: el, isTyping: true)
        XCTAssertEqual(center, CGPoint(x: 400, y: 400))
    }

    func testNonTypingUsesMouseLocation() {
        let el = AXFocusedElement(role: "AXTextArea", frame: CGRect(x: 200, y: 300, width: 400, height: 200))
        let mouse = CGPoint(x: 10, y: 10)
        XCTAssertEqual(resolver.attentionCenter(mouseLocation: mouse, focusedElement: el, isTyping: false), mouse)
    }

    func testTypingWithoutFocusFallsBackToMouse() {
        let mouse = CGPoint(x: 42, y: 42)
        XCTAssertEqual(resolver.attentionCenter(mouseLocation: mouse, focusedElement: nil, isTyping: true), mouse)
    }

    func testRegionFromFakeProvider() {
        struct FakeProvider: AXFocusProviding {
            let element: AXFocusedElement?
            func focusedElement() -> AXFocusedElement? { element }
        }
        let el = AXFocusedElement(role: "AXTextField", frame: CGRect(x: 90, y: 90, width: 20, height: 20))
        let region = resolver.region(from: FakeProvider(element: el))
        XCTAssertEqual(region?.role, "AXTextField")
        XCTAssertEqual(region?.rect.width, 600)
        XCTAssertNil(resolver.region(from: FakeProvider(element: nil)))
    }
}
