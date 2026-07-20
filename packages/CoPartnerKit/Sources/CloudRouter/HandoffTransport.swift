import Foundation
import CoPartnerCore
// 交棒傳輸縫合點：吃組好的 HandoffRequest，回串流 ProposedAction。
// CI 用假 transport 驗編排；真傳輸（LiteLLM → Claude computer-use、網路呼叫）🔒 step 53。

public protocol HandoffTransport: Sendable {
    func stream(_ request: HandoffRequest) -> AsyncThrowingStream<ProposedAction, Error>
}

public enum HandoffError: Error, Equatable {
    case noTransport
}
