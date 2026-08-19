import XCTest
import ActionExecutor

/// step 55：XPC 客戶端的「只完成一次」保證。
///
/// 它包住的是 `CheckedContinuation`，而**重複 resume 不是回錯值，是直接 crash**。
/// 這種錯誤在真機上表現為「偶爾閃退」，重現條件是競態，靠 dogfood 幾乎抓不到——
/// 所以要在這裡用多執行緒去撞它。
///
/// ⚠️ 測試本身也不能捕捉可變區域變數：完成閉包是 `@Sendable`，
/// 捕捉 `var` 在 Swift 6 下直接編譯失敗（第一版就這樣紅了）。用下方的 `Recorder`。
final class SingleCompletionTests: XCTestCase {

    func testSucceedDeliversOnce() {
        let recorder = Recorder()
        let box = SingleCompletion<Int> { recorder.record($0) }
        box.succeed(1)
        box.succeed(2)
        XCTAssertEqual(recorder.entries, ["success(1)"], "第二次完成必須被吞掉")
        XCTAssertTrue(box.isCompleted)
    }

    /// 先失敗後成功也一樣——**先到先贏**，不是「成功優先」。
    /// XPC 的錯誤處理器可能比 reply 早到，那時該回報的就是錯誤。
    func testFirstOutcomeWinsRegardlessOfKind() {
        let recorder = Recorder()
        let box = SingleCompletion<Int> { recorder.record($0) }
        box.fail(CocoaError(.fileNoSuchFile))
        box.succeed(99)
        XCTAssertEqual(recorder.entries, ["failure"])
    }

    /// **這條是重點**：多條路徑同時搶著完成時，底層動作只能被執行一次。
    /// 真實情境是 reply 與逾時在不同佇列上競爭。
    func testConcurrentCompletionsInvokeActionExactlyOnce() {
        for round in 0..<200 {                   // 重複多輪提高撞到競態的機率
            let recorder = Recorder()
            let box = SingleCompletion<Int> { recorder.record($0) }
            DispatchQueue.concurrentPerform(iterations: 8) { index in
                if index.isMultiple(of: 2) {
                    box.succeed(index)
                } else {
                    box.fail(CocoaError(.fileNoSuchFile))
                }
            }
            XCTAssertEqual(recorder.count, 1,
                           "第 \(round) 輪：完成動作被執行了 \(recorder.count) 次")
        }
    }

    /// 完成之後才到的逾時是 no-op——這正是 XPC 客戶端的常態：
    /// 正常回覆先到，10 秒後那個逾時閉包仍然會執行。
    func testLateTimeoutAfterReplyIsNoOp() {
        let recorder = Recorder()
        let box = SingleCompletion<String> { recorder.record($0) }
        box.succeed("reply")
        box.fail(CocoaError(.timeOut))           // 模擬逾時閉包晚到
        XCTAssertEqual(recorder.entries, ["success(reply)"])
    }

    /// 從未完成時不該有任何呼叫（也不該有隱含的預設值）。
    func testNeverCompletedInvokesNothing() {
        let recorder = Recorder()
        let box = SingleCompletion<Int> { recorder.record($0) }
        XCTAssertEqual(recorder.count, 0)
        XCTAssertFalse(box.isCompleted)
    }
}

/// 執行緒安全的記錄器。完成閉包是 `@Sendable`，不能捕捉可變區域變數。
private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []

    func record<Value>(_ result: Result<Value, Error>) {
        let entry: String
        switch result {
        case .success(let value): entry = "success(\(value))"
        case .failure: entry = "failure"
        }
        lock.lock(); stored.append(entry); lock.unlock()
    }

    var entries: [String] { lock.lock(); defer { lock.unlock() }; return stored }
    var count: Int { entries.count }
}
