import Foundation
import CoPartnerCore
// 交棒傳輸縫合點：吃組好的 HandoffRequest，回串流 ProposedAction。
// CI 用假 transport 驗編排；真傳輸（LiteLLM → Claude computer-use、網路呼叫）🔒 step 53。

public protocol HandoffTransport: Sendable {
    func stream(_ request: HandoffRequest) -> AsyncThrowingStream<ProposedAction, Error>
}

public enum HandoffError: Error, Equatable {
    case noTransport
    /// 沒有設定 `HandoffRequestBuilder`。computer-use 的 `display_width_px` /
    /// `display_height_px` 是必填、且**無法安全給預設值**——填錯不會報錯，只會讓
    /// Claude 回傳的座標全部偏掉。寧可在這裡明確失敗，也不要拿假的螢幕尺寸矇混過去。
    case noRequestBuilder
}
