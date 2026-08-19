import Foundation
// 設計：step 55 ①② 的 XPC 客戶端。
//
// 一個非同步結果有**多條互相競爭的完成路徑**時，保證它只被完成一次。
// XPC 的情況正是如此：reply、錯誤處理器、中斷、失效、逾時，五條路都可能觸發，
// 而且各自在不同的佇列上。
//
// 為什麼值得單獨抽出來測：它包住的是 `CheckedContinuation`，而
// **重複 resume 不是回錯值，是直接 crash**。這種錯誤在真機上表現為
// 「偶爾閃退」，重現條件是競態，靠 dogfood 幾乎抓不到。
// 抽成不依賴 continuation 的形狀之後，CI 就能用多執行緒去撞它。

/// 只會完成一次的結果通道。
public final class SingleCompletion<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var complete: (@Sendable (Result<Value, Error>) -> Void)?

    /// - Parameter complete: 實際的完成動作（例如 `continuation.resume(with:)`）。
    ///   **保證最多被呼叫一次。**
    public init(_ complete: @escaping @Sendable (Result<Value, Error>) -> Void) {
        self.complete = complete
    }

    public func succeed(_ value: Value) { finish(.success(value)) }
    public func fail(_ error: Error) { finish(.failure(error)) }

    /// 是否已經完成。**僅供測試與診斷**——不要拿它來做「先檢查再完成」的判斷，
    /// 那在檢查與完成之間有空隙，正是這個型別要消滅的東西。
    public var isCompleted: Bool {
        lock.lock(); defer { lock.unlock() }
        return complete == nil
    }

    private func finish(_ result: Result<Value, Error>) {
        // 先在鎖內把 closure 取走再放鎖，之後才呼叫——
        // 持鎖呼叫外部程式碼是死鎖的常見來源（對方可能同步再打回來）。
        lock.lock()
        let action = complete
        complete = nil
        lock.unlock()
        action?(result)
    }
}
