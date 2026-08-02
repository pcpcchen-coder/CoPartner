import Foundation
import CoPartnerCore
// 設計：docs/design/v2_smart-capture-engine.md §C（三層記憶）+ v2.1 §3（劇本＝檢索主幹）。
// L2 溫層：ActionStep 文字化 → embed → 存入 VectorIndex；search 以查詢向量做 KNN 撈回 step。
// 預設 InMemoryVectorIndex + HashingEmbedder（CI / 開發）；真機換 SQLiteVecIndex（🔒 step 36）
// 與語意 embedder（step 38+）。L1 熱環見 L1HotBuffer；L3 加密日摘要留 step 54+。

public actor MemoryStore {
    private var index: any VectorIndex
    private let embedder: any TextEmbedder
    private var steps: [UUID: ActionStep] = [:]

    public init(index: any VectorIndex = InMemoryVectorIndex(),
                embedder: any TextEmbedder = HashingEmbedder()) {
        self.index = index
        self.embedder = embedder
    }

    public func insert(step: ActionStep) async {
        let vec = embedder.embed(Self.embedText(for: step))
        try? index.insert(id: step.id, vector: vec)   // 佔位後端會 throw；InMemory 正常
        steps[step.id] = step
    }

    public func search(query: String, k: Int = 8) async -> [ActionStep] {
        let hits = index.knn(query: embedder.embed(query), k: k)
        return hits.compactMap { steps[$0.id] }
    }

    /// 已存的 step 數（除錯 / 測試用）。
    public var count: Int { steps.count }

    /// ActionStep → 可 embed 的文字（app + 類別 + 敘述 + 推測目標）。
    static func embedText(for step: ActionStep) -> String {
        "\(step.app) \(step.category) \(step.whatHappened) \(step.inferredGoal)"
    }
}
