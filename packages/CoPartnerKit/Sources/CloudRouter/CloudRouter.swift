import Foundation
import CoPartnerCore
// 設計：docs/design/v2_smart-capture-engine.md §E + §E.1（ADR-0007）+ v1 §D
// 本地優先的分層推理階梯：小範圍辨識留在本地（OCR / FM 3B / Qwen），
// 只有「大變動 / 本地信心不足 / 跨視窗多步任務」才升級雲端 Claude；敏感內容一律不出境。
// TODO: 經 LiteLLM Gateway 呼叫 Claude（computer-use-2025-11-24, computer_20251124）
// TODO: prompt caching（reference / 系統 prompt 穩定前綴）
// TODO: PIPL guard — 含上海團隊個資/敏感 tile → 強制 local-only，不出境

public actor CloudRouter {
    private var policy = EscalationPolicy()
    private let transport: (any HandoffTransport)?
    private let requestBuilder: HandoffRequestBuilder

    public init(transport: (any HandoffTransport)? = nil,
                requestBuilder: HandoffRequestBuilder = HandoffRequestBuilder()) {
        self.transport = transport
        self.requestBuilder = requestBuilder
    }

    /// 依當前變動訊號決定這次該跑哪一階推理（本地優先，§E.1 / ADR-0007）。
    /// 回傳 `.cloud` 代表「大變動」——呼叫端應打包 ContextEnvelope 並呼叫 `handoff`；
    /// 其餘階交給本地 pipeline（OCR / FM 3B / Qwen）處理。
    public func route(_ signal: RoutingSignal, now: Date = Date()) -> InferenceTier {
        policy.decide(signal, now: now)
    }

    /// 將 ContextEnvelope 交棒給雲端 computer-use，回傳串流提議動作（穩定前綴在前命中 prompt cache）。
    /// 僅在 `route(_:)` 判定為 `.cloud` 時呼叫。真傳輸注入（CI 假 transport；真呼叫 🔒 step 53）。
    public func handoff(_ envelope: ContextEnvelope,
                        systemPrompt: String = "",
                        referencePrefix: String = "") -> AsyncThrowingStream<ProposedAction, Error> {
        guard let transport else {
            return AsyncThrowingStream { $0.finish(throwing: HandoffError.noTransport) }
        }
        let request = requestBuilder.build(envelope: envelope,
                                           systemPrompt: systemPrompt,
                                           referencePrefix: referencePrefix)
        return transport.stream(request)
    }
}

/// 本地↔雲端分層推理的升級策略（ADR-0007 / §E.1）。
/// 純決策、可單元測試；CloudRouter 持有一份並在每次變動時 `decide`。
/// 門檻為保守起點，須於 M5 真機以「誤升級率 / 漏升級率 / 延遲 / 每日 token」調校。
public struct EscalationPolicy: Sendable {
    /// 變動 tile 佔畫面比例 ≥ 此值 → 視為「大變動」，升級雲端。
    public var bigChangeAreaRatio: Double
    /// 本地模型信心 < 此值 → 本地看不懂，升級雲端。
    public var minLocalConfidence: Double
    /// 兩次雲端升級的最小間隔（防 thrash / 控成本）。
    public var cloudCooldown: TimeInterval

    private var lastEscalation = Date.distantPast

    public init(bigChangeAreaRatio: Double = 0.35,
                minLocalConfidence: Double = 0.5,
                cloudCooldown: TimeInterval = 4.0) {
        self.bigChangeAreaRatio = bigChangeAreaRatio
        self.minLocalConfidence = minLocalConfidence
        self.cloudCooldown = cloudCooldown
    }

    /// 本地優先決策：先看能否留在本地，再判斷是否「大變動」需升級雲端。
    public mutating func decide(_ s: RoutingSignal, now: Date = Date()) -> InferenceTier {
        // 0) 隱私閘門最優先：敏感 / 上海團隊個資 → 一律封頂本地，永不出境（ADR-0005 / §G）。
        if s.containsSensitive { return min(localTier(for: s), .localVLM) }

        // 1) 這次「若不升級」該跑的本地階。
        let local = localTier(for: s)

        // 2) 升級條件（任一成立即為「大變動」）：
        //    大面積變動（§B.2 dHash 聚合）/ 本地信心不足 / 需跨視窗多步規劃。
        let wantsCloud = s.dirtyAreaRatio >= bigChangeAreaRatio
            || s.localConfidence < minLocalConfidence
            || s.crossWindowTask

        // 3) 冷卻窗內不重複升級（連續大變動 coalesce，類比 ADR-0006 連點處理）。
        if wantsCloud, now.timeIntervalSince(lastEscalation) >= cloudCooldown {
            lastEscalation = now
            return .cloud
        }

        // 4) 留在本地：想升級但在冷卻中 → 暫用最強本地階（VLM）頂著。
        return wantsCloud ? max(local, .localVLM) : local
    }

    /// 把變動規模與注意力映射到本地階（OCR < 意圖 < VLM）。
    private func localTier(for s: RoutingSignal) -> InferenceTier {
        if s.dirtyAreaRatio < 0.05 { return .localOCR }                       // 幾乎沒變：只跑 dirty-tile OCR
        if s.contextSwitched || s.attentionEnergy >= 0.7 { return .localVLM } // 換版面 / 高注意力焦點 → 視覺語意
        if s.attentionEnergy < 0.4 { return .localOCR }                       // 低注意力：文字就夠
        return .localIntent                                                   // 其餘：FM 3B 意圖 / 路由
    }
}
