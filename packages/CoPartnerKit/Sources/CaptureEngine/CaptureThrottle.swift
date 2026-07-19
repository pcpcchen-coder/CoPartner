import Foundation
import CoPartnerCore
// 設計：§B.6 表格（tile 狀態 → 該不該 OCR / 存 delta）。純決策、CI 可測。
// COLD 不 OCR；WARM（剛變動）OCR；HOT 節流 OCR；DYNAMIC（影片）跳 OCR、不存 delta。

public struct CaptureThrottle: Sendable, Equatable {
    /// HOT tile 兩次 OCR 的最小間隔（避免打字爆 OCR）。
    public var hotOCRInterval: TimeInterval
    public init(hotOCRInterval: TimeInterval = 0.5) { self.hotOCRInterval = max(0, hotOCRInterval) }

    /// 該 tile 這次要不要跑 OCR。
    public func shouldOCR(state: TileEvent.State, sinceLastOCR: TimeInterval) -> Bool {
        switch state {
        case .cold:    return false                          // 靜置：不 OCR
        case .warm:    return true                           // 剛變動：OCR
        case .hot:     return sinceLastOCR >= hotOCRInterval // 頻繁變動：節流
        case .dynamic: return false                          // 影片：跳 OCR
        }
    }

    /// 該 tile 這次要不要存 delta（影片不存，§B.6）。
    public func shouldPersistDelta(state: TileEvent.State) -> Bool {
        state != .dynamic
    }
}
