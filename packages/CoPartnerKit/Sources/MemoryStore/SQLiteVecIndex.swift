import Foundation
// 🔒 step 36：真 sqlite-vec（vec0 虛擬表 float[768]）綁定。
// 此檔目前為型別佔位——鎖住 VectorIndex 縫合點；真 sqlite3 open / load_extension("vec0") /
// CREATE VIRTUAL TABLE ... USING vec0 / KNN 查詢在真機接線與驗證（extension 載入、磁碟持久化皆 🔒）。
// 佔位期間 insert 直接 throw（.notWired，絕不靜默假裝存了），knn 回空——避免以為存了其實沒存。

public final class SQLiteVecIndex: VectorIndex, @unchecked Sendable {
    public let dimension: Int
    public init(dimension: Int = 768) { self.dimension = max(1, dimension) }

    public func insert(id: UUID, vector: [Float]) throws {
        throw VectorIndexError.notWired
    }

    public func knn(query: [Float], k: Int) -> [(id: UUID, distance: Float)] {
        []
    }
}
