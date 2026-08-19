import XCTest
import ActionExecutor

/// step 53.4 的純值部分：**餵給 `posix_spawn` 的東西長什麼樣**。
///
/// `posix_spawn` 本身測不到（在 XPC service 裡、要真機），但它不會出錯——
/// 錯的是我們給它什麼。所以安全性其實全在這一層，而這一層完全可以在 CI 驗。
final class SandboxedCommandTests: XCTestCase {

    private func command(_ argv: [String],
                         profile: String = "/tmp/p.sb") throws -> SandboxedCommand {
        try SandboxedCommand(argv: argv, profilePath: profile, timeout: .seconds(30))
    }

    // MARK: - I4：沒有任何一步把 argv 拼成字串

    /// **最重要的一條**：帶空白與 shell metacharacter 的參數必須原樣是**一個**元素。
    /// 只要中間有一次 `joined(separator: " ")`，這種參數就會被重新切分——那就是 injection。
    func testArgvElementsSurviveIntoSpawnArgumentsIntact() throws {
        let nasty = ["/bin/echo", "a b; rm -rf /", "$(whoami)", "|", "&&", "'quoted'"]
        let spawn = try command(nasty).spawnArguments
        XCTAssertEqual(Array(spawn.suffix(nasty.count)), nasty,
                       "argv 元素邊界不可在任何一步被改變")
    }

    /// 完整形狀：sandbox-exec -f <profile> <argv…>
    func testSpawnArgumentsShape() throws {
        let spawn = try command(["/bin/cat", "/tmp/x"], profile: "/tmp/p.sb").spawnArguments
        XCTAssertEqual(spawn, ["/usr/bin/sandbox-exec", "-f", "/tmp/p.sb", "/bin/cat", "/tmp/x"])
    }

    /// profile 走 `-f 檔案`，不可內嵌進命令列——命令列上的東西會出現在 `ps` 裡，
    /// 等於把安全設定公開給同機所有程序看。
    func testProfileIsPassedByFileNotInline() throws {
        let spawn = try command(["/bin/cat"], profile: "/tmp/p.sb").spawnArguments
        XCTAssertFalse(spawn.contains("-p"), "不可用 -p 內嵌 profile 文字")
        XCTAssertTrue(spawn.contains("-f"))
    }

    // MARK: - 路徑必須絕對

    /// 相對路徑會經由 PATH 解析，執行到什麼取決於環境變數——正是沙箱要消滅的不確定性。
    /// 而且 profile 的 exec 白名單用絕對路徑比對，相對路徑必然對不上。
    func testRelativeCommandIsRejected() {
        XCTAssertThrowsError(try command(["cat", "/tmp/x"])) { error in
            XCTAssertEqual(error as? SandboxedCommandError, .commandNotAbsolute("cat"))
        }
    }

    func testRelativeProfilePathIsRejected() {
        XCTAssertThrowsError(try command(["/bin/cat"], profile: "p.sb"))
    }

    func testEmptyArgvIsRejected() {
        XCTAssertThrowsError(try command([])) { error in
            XCTAssertEqual(error as? SandboxedCommandError, .emptyArgv)
        }
    }

    /// 絕對路徑的另一個好處：命令不可能以 `-` 開頭被 sandbox-exec 當成自己的旗標。
    func testCommandCannotBeMistakenForALauncherFlag() throws {
        let spawn = try command(["/bin/cat"]).spawnArguments
        let commandIndex = try XCTUnwrap(spawn.firstIndex(of: "/bin/cat"))
        XCTAssertFalse(spawn[commandIndex].hasPrefix("-"))
    }

    // MARK: - 結果分類

    /// 分這麼細是因為它們要修的東西完全不同：命令自己失敗、沙箱擋住、
    /// 啟動失敗、逾時。全歸成「失敗」的話稽核就失去診斷價值。
    func testClassification() {
        XCTAssertEqual(CommandOutcomeClassifier.classify(exitCode: 0), .succeeded)
        XCTAssertEqual(CommandOutcomeClassifier.classify(exitCode: 1), .failed(exitCode: 1))
        XCTAssertEqual(CommandOutcomeClassifier.classify(exitCode: 71),
                       .launchFailed(exitCode: 71))
        XCTAssertEqual(CommandOutcomeClassifier.classify(exitCode: 0, signal: 9),
                       .killedBySignal(9))
    }

    /// 逾時優先於訊號：逾時被殺的程序也會帶訊號，順序反了會把它誤報成「被訊號殺掉」，
    /// 而那兩件事的處理方式不同（前者要調逾時或看命令為何卡住）。
    func testTimeoutTakesPrecedenceOverSignal() {
        XCTAssertEqual(
            CommandOutcomeClassifier.classify(exitCode: 0, signal: 9, timedOut: true),
            .timedOut)
    }

    /// `didExecute` 決定稽核與 HUD 敢不敢說「已執行」。
    /// 命令跑完但回非零**算執行過**（副作用可能已經發生）；沒起來的才不算。
    func testDidExecuteDistinguishesRanFromNeverStarted() {
        XCTAssertTrue(CommandDisposition.succeeded.didExecute)
        XCTAssertTrue(CommandDisposition.failed(exitCode: 1).didExecute,
                      "跑完才失敗的命令，副作用可能已經發生")
        XCTAssertFalse(CommandDisposition.launchFailed(exitCode: 71).didExecute)
        XCTAssertFalse(CommandDisposition.timedOut.didExecute,
                       "⚠️ 逾時其實可能已經做了一半——這裡回 false 是**保守偏向不宣稱執行**，"
                       + "而不是斷言什麼都沒發生")
    }

    // MARK: - 輸出截斷

    /// 截斷一定要留標記。沒有標記的話，被截掉的輸出看起來就像「命令只講了這麼多」——
    /// 稽核紀錄一旦讓人誤以為看到全部，它就從證據變成誤導。
    func testTruncationIsMarked() {
        let long = String(repeating: "x", count: 5_000)
        let result = OutputTruncator.truncate(long, limit: 100)
        XCTAssertTrue(result.hasPrefix(String(repeating: "x", count: 100)))
        XCTAssertTrue(result.contains("已截斷 4900 個字元"), "實際：\(result.suffix(40))")
    }

    func testShortOutputIsUntouched() {
        XCTAssertEqual(OutputTruncator.truncate("hello", limit: 100), "hello")
    }

    /// 剛好等於上限時不截斷——邊界差一個字就多一行雜訊。
    func testExactLimitIsNotTruncated() {
        let exact = String(repeating: "y", count: 100)
        XCTAssertEqual(OutputTruncator.truncate(exact, limit: 100), exact)
    }
}
