import Foundation
import ActionExecutor

// 🔒 真機膠水：實際的 `posix_spawn`（第 53.4-B 段）。CI 只保證編譯。
//
// **step 53.5 起這個檔會真的被呼叫**——`ExecutorService.willExecuteActions` 已翻成 true。
// 在此之前它只被編譯、從未執行過，所以下面三點的每一點都還沒被真機證實過，
// 只被推理與測試涵蓋過；真機上第一次出問題最可能就在這三點裡。
//
// 三個一定要做對的地方，做錯的後果都不是「失敗」而是更糟的東西：
//
// 1. **邊讀邊等，不可先等再讀。** pipe 緩衝區只有幾十 KB，輸出多的命令會把它填滿然後
//    卡在 write 上；此時若父程序還在 waitpid，兩邊互等——**永遠不會結束**。
//    所以兩條 pipe 各自在背景佇列上排乾，waitpid 才收屍。
// 2. **不繼承環境變數。** 見 `SandboxedCommand.minimalEnvironment`。
// 3. **逾時一定要真的殺掉。** 逾時只是「不再等」的話，那個程序還在跑、還在動檔案，
//    而我們已經回報「逾時」了——那是最糟的一種不誠實：使用者以為停了，其實沒有。
final class SandboxedCommandRunner {

    struct Output {
        let disposition: CommandDisposition
        let stdout: String
        let stderr: String
    }

    enum RunnerError: Error, CustomStringConvertible {
        case cannotWriteProfile(String)
        case spawnFailed(Int32)

        var description: String {
            switch self {
            case .cannotWriteProfile(let d): return "無法寫入 profile：\(d)"
            case .spawnFailed(let code): return "posix_spawn 失敗（errno \(code)）"
            }
        }
    }

    /// 執行一個沙箱命令。**同步**——呼叫端是 XPC 的工作佇列，本來就允許阻塞。
    func run(argv: [String], profile: String, workspace: SandboxWorkspace,
             timeout: Duration) throws -> Output {
        // 目錄由 `SandboxWorkspace` 決定——單一事實來源，乾跑報告才不會跟實際漂開。
        let profilePath = try writeProfile(profile, in: workspace.profileDirectory)
        defer { try? FileManager.default.removeItem(atPath: profilePath) }

        let command = try SandboxedCommand(argv: argv, profilePath: profilePath, timeout: timeout)
        return try spawn(command,
                         environment: SandboxedCommand.minimalEnvironment(home: workspace.root))
    }

    /// profile 寫到**沙箱碰不到的地方**、權限 0600。
    ///
    /// ⚠️ 第一版寫在工作目錄裡，那是錯的：工作目錄是沙箱**唯一可寫**的地方，
    /// 所以被關住的命令讀得到也寫得到那份 profile——等於把「哪些路徑被視為秘密」
    /// 的地圖交給它。真機乾跑報告一眼看出來的。
    ///
    /// 改放工作目錄的**兄弟目錄**（沙箱的 deny-default 蓋得到）。這是安全的，因為
    /// `sandbox-exec` 是在**套用沙箱之前**讀 profile 的——那個檔從來不需要在
    /// 沙箱可及範圍內。
    private func writeProfile(_ profile: String, in directory: String) throws -> String {
        let path = (directory as NSString)
            .appendingPathComponent(".copartner-sandbox-\(UUID().uuidString).sb")
        do {
            try profile.write(toFile: path, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        } catch {
            throw RunnerError.cannotWriteProfile("\(error)")
        }
        return path
    }

    private func spawn(_ command: SandboxedCommand, environment: [String]) throws -> Output {
        var outPipe: [Int32] = [0, 0]
        var errPipe: [Int32] = [0, 0]
        guard pipe(&outPipe) == 0, pipe(&errPipe) == 0 else {
            throw RunnerError.spawnFailed(errno)
        }

        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        posix_spawn_file_actions_adddup2(&fileActions, outPipe[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, errPipe[1], STDERR_FILENO)
        // 子程序不需要 pipe 的讀端，關掉；留著會讓「寫端全關」的判斷永遠不成立。
        posix_spawn_file_actions_addclose(&fileActions, outPipe[0])
        posix_spawn_file_actions_addclose(&fileActions, errPipe[0])

        var pid: pid_t = 0
        let status = withCStrings(command.spawnArguments) { argv in
            withCStrings(environment) { envp in
                posix_spawn(&pid, SandboxedCommand.launcher, &fileActions, nil, argv, envp)
            }
        }
        // 父程序關掉寫端：不關的話 read 永遠等不到 EOF，排乾那一步不會結束。
        close(outPipe[1]); close(errPipe[1])
        guard status == 0 else {
            close(outPipe[0]); close(errPipe[0])
            throw RunnerError.spawnFailed(status)
        }

        // ⚠️ 先排乾、再收屍。順序反了就是死結——見檔頭第 1 點。
        let group = DispatchGroup()
        let collected = OutputCollector()
        drain(fd: outPipe[0], into: collected, isStdout: true, group: group)
        drain(fd: errPipe[0], into: collected, isStdout: false, group: group)

        let timedOut = waitWithTimeout(pid: pid, timeout: command.timeout)
        group.wait()

        return Output(disposition: CommandOutcomeClassifier.classify(
                        exitCode: timedOut.exitCode, signal: timedOut.signal,
                        timedOut: timedOut.didTimeOut),
                      stdout: OutputTruncator.truncate(collected.stdout),
                      stderr: OutputTruncator.truncate(collected.stderr))
    }

    private func drain(fd: Int32, into collector: OutputCollector,
                       isStdout: Bool, group: DispatchGroup) {
        DispatchQueue.global().async(group: group) {
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let n = read(fd, &buffer, buffer.count)
                if n <= 0 { break }
                data.append(contentsOf: buffer[0..<n])
            }
            close(fd)
            collector.append(String(decoding: data, as: UTF8.self), isStdout: isStdout)
        }
    }

    /// 等子程序結束，逾時就 SIGKILL。
    ///
    /// 用輪詢（WNOHANG + 短睡）而不是 `DispatchSource`：這裡已經在一條專屬的
    /// XPC 工作執行緒上，輪詢的程式碼短到可以一眼看完，而正確性比省那點 CPU 重要。
    private func waitWithTimeout(pid: pid_t, timeout: Duration)
        -> (exitCode: Int32, signal: Int32?, didTimeOut: Bool) {
        let deadline = ContinuousClock.now + timeout
        var info: Int32 = 0
        while true {
            let result = waitpid(pid, &info, WNOHANG)
            if result == pid { break }
            if result < 0 { return (exitCode: -1, signal: nil, didTimeOut: false) }
            if ContinuousClock.now >= deadline {
                kill(pid, SIGKILL)                    // 真的殺掉，不只是不再等
                _ = waitpid(pid, &info, 0)            // 收屍，避免殭屍程序
                return (exitCode: -1, signal: nil, didTimeOut: true)
            }
            usleep(20_000)                            // 20ms
        }
        if info & 0x7f != 0 {                         // WIFSIGNALED
            return (exitCode: -1, signal: info & 0x7f, didTimeOut: false)
        }
        return (exitCode: (info >> 8) & 0xff, signal: nil, didTimeOut: false)
    }
}

/// 兩條 pipe 在不同佇列上寫進來，要有鎖。
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var out = ""
    private var err = ""
    func append(_ text: String, isStdout: Bool) {
        lock.lock(); defer { lock.unlock() }
        if isStdout { out += text } else { err += text }
    }
    var stdout: String { lock.lock(); defer { lock.unlock() }; return out }
    var stderr: String { lock.lock(); defer { lock.unlock() }; return err }
}

/// Swift 字串陣列 → C 的 `char *[]`（結尾 NULL）。
/// 用 closure 包住是為了讓 strdup 出來的記憶體有明確的釋放點。
private func withCStrings<R>(_ strings: [String],
                             _ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> R) -> R {
    var pointers: [UnsafeMutablePointer<CChar>?] = strings.map { strdup($0) }
    pointers.append(nil)
    defer { for p in pointers where p != nil { free(p) } }
    return pointers.withUnsafeMutableBufferPointer { body($0.baseAddress!) }
}
