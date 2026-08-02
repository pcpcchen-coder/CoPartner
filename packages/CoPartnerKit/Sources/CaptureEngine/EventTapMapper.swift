import CoreGraphics
// 設計：docs/design/v2_smart-capture-engine.md §B.3 / §B.3.1
// 純映射邏輯（可單元測試）。真正的 CGEventTap 膠水在 InputEventTap（🔒 真機）。

/// 把一個輸入事件（CGEventType + 滑鼠位移）映射成注意力訊號。
/// 與 tap 膠水分離，讓「哪種事件 → 哪種 Signal」可離線測試。
public enum EventTapMapper {
    /// - Parameters:
    ///   - type: CGEventType。
    ///   - mouseDelta: 滑鼠位移（僅 `.mouseMoved` 用到），用來推估移動速度。
    ///   - fastMoveDelta: 視為「最快移動」的單事件位移量（pt）；達此值 → speed=1（快移不升級注意力，§B.3.1）。
    /// - Returns: 對應的 `AttentionModel.Signal`；不關心的事件回 `nil`。
    public static func signal(for type: CGEventType,
                              mouseDelta: CGVector = .zero,
                              fastMoveDelta: Double = 40) -> AttentionModel.Signal? {
        switch type {
        case .leftMouseDown, .rightMouseDown:       return .click   // 動作起點
        case .leftMouseDragged, .rightMouseDragged: return .drag    // 選取 / 拖曳進行中
        case .keyDown:                              return .keyDown // 錨定 focused element（§B.4）
        case .scrollWheel:                          return .scroll  // 內容在游標下變動，偏閱讀
        case .mouseMoved:
            let dx = Double(mouseDelta.dx), dy = Double(mouseDelta.dy)
            let magnitude = (dx * dx + dy * dy).squareRoot()
            let speed = min(magnitude / max(fastMoveDelta, 1), 1.0)  // 快移→speed 高→注意力低
            return .move(speed: speed)
        default:                                    return nil      // keyUp / flagsChanged / otherMouse…
        }
    }
}
