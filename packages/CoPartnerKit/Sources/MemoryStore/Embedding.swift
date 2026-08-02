import Foundation
// 把文字（劇本 / 查詢）轉成向量。真後端（FoundationModels 句向量 / 本地模型）留 step 38+；
// 這裡先給確定性 HashingEmbedder 佔位，讓 MemoryStore 有可用預設，測試可注入自訂 embedder。

public protocol TextEmbedder: Sendable {
    var dimension: Int { get }
    func embed(_ text: String) -> [Float]
}

/// 確定性 bag-of-characters 雜湊向量（L2 normalize）。**非語意**，僅佔位 / 開發用。
public struct HashingEmbedder: TextEmbedder {
    public let dimension: Int
    public init(dimension: Int = 768) { self.dimension = max(1, dimension) }

    public func embed(_ text: String) -> [Float] {
        var v = [Float](repeating: 0, count: dimension)
        for scalar in text.unicodeScalars {
            v[Int(scalar.value) % dimension] += 1
        }
        let norm = v.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
        if norm > 0 {
            for i in 0..<dimension { v[i] /= norm }
        }
        return v
    }
}
