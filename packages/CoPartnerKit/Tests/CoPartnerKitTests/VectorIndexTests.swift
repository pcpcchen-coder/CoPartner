import XCTest
import MemoryStore

/// 向量索引 KNN 邏輯（§C）：純 Swift InMemoryVectorIndex 驗排序 / k / 維度；佔位 SQLite 後端拒寫。
final class VectorIndexTests: XCTestCase {
    func testKNNNearestFirst() throws {
        var idx = InMemoryVectorIndex(dimension: 2)
        let a = UUID(), b = UUID(), c = UUID()
        try idx.insert(id: a, vector: [0, 0])
        try idx.insert(id: b, vector: [1, 0])
        try idx.insert(id: c, vector: [5, 0])
        let hits = idx.knn(query: [0.9, 0], k: 3)
        XCTAssertEqual(hits.map { $0.id }, [b, a, c])   // b 最近、c 最遠
    }

    func testKNNRespectsK() throws {
        var idx = InMemoryVectorIndex(dimension: 2)
        for _ in 0..<5 { try idx.insert(id: UUID(), vector: [0, 0]) }
        XCTAssertEqual(idx.knn(query: [0, 0], k: 2).count, 2)
    }

    func testKNNEmptyIndexEmpty() {
        let idx = InMemoryVectorIndex(dimension: 4)
        XCTAssertTrue(idx.knn(query: [0, 0, 0, 0], k: 3).isEmpty)
    }

    func testKNNDistancesMonotonic() throws {
        var idx = InMemoryVectorIndex(dimension: 1)
        let near = UUID(), far = UUID()
        try idx.insert(id: near, vector: [1])
        try idx.insert(id: far, vector: [9])
        let hits = idx.knn(query: [0], k: 2)
        XCTAssertEqual(hits.first?.id, near)
        XCTAssertLessThan(hits[0].distance, hits[1].distance)
    }

    func testDimensionMismatchThrows() {
        var idx = InMemoryVectorIndex(dimension: 768)
        XCTAssertThrowsError(try idx.insert(id: UUID(), vector: [1, 2, 3])) { err in
            XCTAssertEqual(err as? VectorIndexError, .dimensionMismatch(expected: 768, got: 3))
        }
    }

    func testSkeletonSQLiteIndexRefusesWrite() {
        let idx = SQLiteVecIndex(dimension: 768)
        XCTAssertThrowsError(try idx.insert(id: UUID(), vector: [Float](repeating: 0, count: 768))) { err in
            XCTAssertEqual(err as? VectorIndexError, .notWired)   // 佔位期不靜默假裝存了
        }
        XCTAssertTrue(idx.knn(query: [Float](repeating: 0, count: 768), k: 3).isEmpty)
    }
}
