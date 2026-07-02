import XCTest
import CoreGraphics
import CaptureEngine

/// CGEventType → AttentionModel.Signal 純映射（§B.3）。真 tap 攔截行為於 step 10 真機驗收。
final class EventTapMapperTests: XCTestCase {
    func testLeftMouseDownMapsToClick() {
        XCTAssertEqual(EventTapMapper.signal(for: .leftMouseDown), .click)
    }

    func testRightMouseDownMapsToClick() {
        XCTAssertEqual(EventTapMapper.signal(for: .rightMouseDown), .click)
    }

    func testLeftDragMapsToDrag() {
        XCTAssertEqual(EventTapMapper.signal(for: .leftMouseDragged), .drag)
    }

    func testKeyDownMapsToKeyDown() {
        XCTAssertEqual(EventTapMapper.signal(for: .keyDown), .keyDown)
    }

    func testScrollWheelMapsToScroll() {
        XCTAssertEqual(EventTapMapper.signal(for: .scrollWheel), .scroll)
    }

    func testUnhandledTypesReturnNil() {
        XCTAssertNil(EventTapMapper.signal(for: .keyUp))
        XCTAssertNil(EventTapMapper.signal(for: .flagsChanged))
        XCTAssertNil(EventTapMapper.signal(for: .otherMouseDown))
    }

    func testFastMoveMapsToHigherSpeedThanSlowMove() {
        // 慢移 → speed 小（注意力較高）；快移 → speed 接近 1（注意力較低，§B.3.1）。
        guard case .move(let slow)? = EventTapMapper.signal(for: .mouseMoved,
                                                            mouseDelta: CGVector(dx: 4, dy: 0),
                                                            fastMoveDelta: 40),
              case .move(let fast)? = EventTapMapper.signal(for: .mouseMoved,
                                                            mouseDelta: CGVector(dx: 80, dy: 0),
                                                            fastMoveDelta: 40)
        else { return XCTFail(".mouseMoved 應映射為 .move") }
        XCTAssertEqual(slow, 0.1, accuracy: 1e-9)   // 4 / 40
        XCTAssertEqual(fast, 1.0, accuracy: 1e-9)   // 80 / 40 → clamp 1
        XCTAssertLessThan(slow, fast)
    }

    func testMoveSpeedClampedToOne() {
        guard case .move(let speed)? = EventTapMapper.signal(for: .mouseMoved,
                                                             mouseDelta: CGVector(dx: 1000, dy: 1000))
        else { return XCTFail(".mouseMoved 應映射為 .move") }
        XCTAssertEqual(speed, 1.0, accuracy: 1e-9)
    }

    func testZeroDeltaMoveHasZeroSpeed() {
        guard case .move(let speed)? = EventTapMapper.signal(for: .mouseMoved, mouseDelta: .zero)
        else { return XCTFail(".mouseMoved 應映射為 .move") }
        XCTAssertEqual(speed, 0.0, accuracy: 1e-9)
    }
}
