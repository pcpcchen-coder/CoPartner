import XCTest
import ActionExecutor

/// step 55：XPC 客戶端的「只完成一次」保證。
///
/// 它包住的是 `CheckedContinuation`，而**重複 resume 不是回錯值，是直接 crash**。
/// 這種錯誤在真機上表現為「偶爾閃退」，重現條件是競態，靠 dogfood 幾乎抓不到——
/// 所以要在這裡用多執行緒去撞它。
final class SingleCompletionTests: XCTestCase {

    func testSucceedDeliversOnce() {
        var results: [Int] = []
        let box = SingleCompletion<Int> { if case .success(let v) = $0 { results.append(v) } }
        box.succeed(1)
        box.succeed(2)
        XCTAssertEqual(results, [1], "第二次完成必須被吞掉")
        XCTAssertTrue(box.isCompleted)
    }

    /// 先失敗後成功也一樣——**先到先贏**，不是「成功優先」。
    /// XPC 的錯誤處理器可能比 reply 早到，那時該回報的就是錯誤。
    func testFirstOutcomeWinsRegardlessOfKind() {
        var count = 0
        var wasFailure = false
        let box = SingleCompletion<Int> { result in
            count += 1
            if case .failure = result { wasFailure = true }
        }
        box.fail(CocoaError(.fileNoSuchFile))
        box.succeed(99)
        XCTAssertEqual(count, 1)
        XCTAssertTrue(wasFailure)
    }

    /// **這條是重點**：多條路徑同時搶著完成時，底層動作只能被執行一次。
    /// 真實情境是 reply 與逾時在不同佇列上競爭。
    func testConcurrentCompletionsInvokeActionExactlyOnce() {
        for _ in 0..<200 {                       // 重複多輪提高撞到競態的機率
            let counter = Counter()
            let box = SingleCompletion<Int> { _ in counter.increment() }
            DispatchQueue.concurrentPerform(iterations: 8) { index in
                if index.isMultiple(of: 2) {
                    box.succeed(index)
                } else {
                    box.fail(CocoaError(.fileNoSuchFile))
                }
            }
            XCTAssertEqual(counter.value, 1, "完成動作被執行了 \(counter.value) 次")
        }
    }

    /// 完成之後才到的逾時是 no-op——這正是 XPC 客戶端的常態：
    /// 正常回覆先到，10 秒後那個逾時閉包仍然會執行。
    func testLateTimeoutAfterReplyIsNoOp() {
        var count = 0
        let box = SingleCompletion<String> { _ in count += 1 }
        box.succeed("reply")
        box.fail(CocoaError(.timeOut))          // 模擬逾時閉包晚到
        XCTAssertEqual(count, 1)
    }

    /// 從未完成時不該有任何呼叫（也不該有隱含的預設值）。
    func testNeverCompletedInvokesNothing() {
        var count = 0
        let box = SingleCompletion<Int> { _ in count += 1 }
        XCTAssertEqual(count, 0)
        XCTAssertFalse(box.isCompleted)
    }
}

/// 執行緒安全的計數器（測試用）。
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = 0
    func increment() { lock.lock(); stored += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return stored }
}
