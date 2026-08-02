import Foundation
// 設計：docs/design/v2_smart-capture-engine.md §C（L2 溫層：sqlite-vec vec0 float[768] KNN）。
// query/ranking 邏輯抽 protocol，CI 用純 Swift InMemoryVectorIndex 驗；真 vec0 綁定 🔒 step 36。

public enum VectorIndexError: Error, Equatable {
    case dimensionMismatch(expected: Int, got: Int)
    case notWired            // 真後端尚未接線（SQLiteVecIndex 佔位）
}

/// 向量索引縫合點：插入 (id, vector)、以查詢向量取最近 k 筆。
public protocol VectorIndex: Sendable {
    var dimension: Int { get }
    mutating func insert(id: UUID, vector: [Float]) throws
    func knn(query: [Float], k: Int) -> [(id: UUID, distance: Float)]
}

/// 純 Swift 平面 KNN（L2 距離）。CI / 開發用；真機大量資料換 SQLiteVecIndex。
public struct InMemoryVectorIndex: VectorIndex {
    public let dimension: Int
    private var ids: [UUID] = []
    private var vectors: [[Float]] = []

    public init(dimension: Int = 768) { self.dimension = max(1, dimension) }

    public mutating func insert(id: UUID, vector: [Float]) throws {
        guard vector.count == dimension else {
            throw VectorIndexError.dimensionMismatch(expected: dimension, got: vector.count)
        }
        ids.append(id)
        vectors.append(vector)
    }

    public func knn(query: [Float], k: Int) -> [(id: UUID, distance: Float)] {
        guard k > 0, query.count == dimension, !ids.isEmpty else { return [] }
        let scored = zip(ids, vectors).map { pair -> (id: UUID, distance: Float) in
            (id: pair.0, distance: Self.l2(pair.1, query))
        }
        return Array(scored.sorted { $0.distance < $1.distance }.prefix(k))
    }

    /// L2（歐氏）距離；越小越近。
    static func l2(_ a: [Float], _ b: [Float]) -> Float {
        var sum: Float = 0
        for i in 0..<Swift.min(a.count, b.count) {
            let d = a[i] - b[i]
            sum += d * d
        }
        return sum.squareRoot()
    }
}
