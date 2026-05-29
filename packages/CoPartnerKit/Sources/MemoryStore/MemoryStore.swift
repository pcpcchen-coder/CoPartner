import Foundation
import CoPartnerCore
// 設計：docs/design/v2_smart-capture-engine.md §C（三層記憶）+ v2.1 §3（劇本=檢索主幹）
// TODO: sqlite-vec（vec0 虛擬表 float[768]）KNN 檢索 ActionStep / L2 摘要
// TODO: L1 RAM ring buffer / L2 SQLite+vec / L3 SQLCipher 加密摘要

public actor MemoryStore {
    public init() {}
    public func insert(step: ActionStep) async { /* TODO */ }
    public func search(query: String, k: Int = 8) async -> [ActionStep] { [] }
}
