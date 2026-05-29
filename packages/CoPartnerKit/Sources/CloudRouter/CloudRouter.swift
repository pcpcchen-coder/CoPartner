import Foundation
import CoPartnerCore
// 設計：docs/design/v2_smart-capture-engine.md §E + v1 §D
// TODO: 經 LiteLLM Gateway 呼叫 Claude（computer-use-2025-11-24, computer_20251124）
// TODO: prompt caching（reference / 系統 prompt 穩定前綴）
// TODO: PIPL guard — 含上海團隊個資/敏感 tile → 強制 local-only，不出境

public actor CloudRouter {
    public init() {}
    /// 將 ContextEnvelope 交棒給雲端大模型，回傳串流動作。
    public func handoff(_ envelope: ContextEnvelope) async throws { /* TODO */ }
}
