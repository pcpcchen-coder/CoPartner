import Foundation
import CoPartnerCore
// 設計：docs/design/v2_smart-capture-engine.md §B
// TODO(M0): SCStream + SCStreamFrameInfo.dirtyRects 解析（§B.1）
// TODO(M0): Metal compute shader per-tile dHash（§B.2，shader 放 Resources/TileHash.metal）
// TODO(M0): CGEventTap mouseMoved 驅動 attention region（§B.3）
// TODO(M1): tile 冷熱狀態機 + DYNAMIC 影片降頻（§B.6）
// TODO(M3): reference frame + delta 重建（§B.7）

public actor CaptureEngine {
    public init() {}
    public func start() async throws { /* TODO */ }
    public func stop() async { /* TODO */ }
}
