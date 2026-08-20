import XCTest
import CoPartnerCore
import ActionExecutor

/// 執行閘門 + 沙箱政策（step 51）：token 世代/綁定、contract 白名單、路徑白名單（含 symlink）、
/// sbpl 產生、速率/迴圈、稽核。token 一律經 TakeoverSessionModel 取得（模組外無法鑄造，I1）。
final class ActionExecutorSandboxTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("copartner-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    /// 建一組共用 clock 的 model+executor，並走正規流程拿 token。
    private func makeStack(policy: SandboxPolicy? = nil,
                           allowlist: PathAllowlist? = nil,
                           limiter: RateLimiter = RateLimiter(),
                           performer: (@Sendable (ProposedAction) async throws -> Void)? = { _ in })
        -> (model: TakeoverSessionModel, executor: ActionExecutor) {
        let clock = HandoffGeneration()
        let model = TakeoverSessionModel(policy: .confirmEach, generationClock: clock)
        let executor = ActionExecutor(
            clock: clock,
            policy: policy ?? SandboxPolicy(allowedTools: ["computer", "bash(sandboxed)", "text_editor"]),
            allowlist: allowlist ?? PathAllowlist(allowedRoots: [tmp.path]),
            limiter: limiter,
            performer: performer)
        return (model, executor)
    }

    private func approvedToken(_ model: inout TakeoverSessionModel, for action: ProposedAction) -> ApprovalToken {
        _ = model.receive(action, risk: .medium)
        guard let token = model.approve() else { fatalError("approve 應鑄造 token") }
        model.finishExecution()
        return token
    }

    private func expectError(_ expected: ExecutionError, _ body: () async throws -> Void,
                             file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await body()
            XCTFail("應丟 \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? ExecutionError, expected, file: file, line: line)
        }
    }

    // MARK: token（I1/I7）

    func testStaleGenerationTokenRejected() async {
        var (model, executor) = makeStack()
        model.begin()
        let a = ProposedAction(kind: .click(x: 1, y: 1))
        let token = approvedToken(&model, for: a)
        model.stop()   // kill-switch：世代作廢
        await expectError(.staleToken) { try await executor.execute(a, token: token) }
    }

    func testTokenActionMismatchRejected() async {
        var (model, executor) = makeStack()
        model.begin()
        let a = ProposedAction(kind: .click(x: 1, y: 1))
        let token = approvedToken(&model, for: a)
        let other = ProposedAction(kind: .click(x: 9, y: 9))   // token 綁 a，不能拿去執行 other
        await expectError(.tokenActionMismatch) { try await executor.execute(other, token: token) }
    }

    // MARK: contract 白名單（T4）

    func testToolOutsideContractRejected() async {
        var (model, executor) = makeStack(policy: SandboxPolicy(allowedTools: ["computer"]))   // 無 bash
        model.begin()
        let a = ProposedAction(kind: .shell(argv: ["echo", "hi"]))
        let token = approvedToken(&model, for: a)
        await expectError(.toolNotAllowed("shell(echo hi)")) { try await executor.execute(a, token: token) }
    }

    func testOutboundCommsNeverInDefaultContract() {
        let policy = SandboxPolicy.from(contract: TakeoverContract(
            instruction: "x", policy: .confirmEach,
            allowedTools: ["text_editor", "bash(sandboxed)", "computer"]))
        XCTAssertFalse(policy.allows(.outboundComms(kind: "email", target: "a@b.c")))
        XCTAssertTrue(policy.allows(.shell(argv: ["ls"])))     // "bash(sandboxed)" 前綴匹配
    }

    // MARK: 路徑白名單（I5）

    func testPathTraversalNormalizedThenRejected() async {
        var (model, executor) = makeStack()
        model.begin()
        let sneaky = tmp.path + "/sub/../../outside-secrets.txt"   // 詞法跳出 tmp root
        let a = ProposedAction(kind: .writeFile(path: sneaky, contents: "x"))
        let token = approvedToken(&model, for: a)
        do {
            try await executor.execute(a, token: token)
            XCTFail("跳脫路徑應被拒")
        } catch let e as ExecutionError {
            guard case .pathOutsideAllowlist = e else { return XCTFail("錯誤類型應為 pathOutsideAllowlist") }
        } catch { XCTFail("非預期錯誤 \(error)") }
    }

    func testSymlinkEscapeRejected() throws {
        // ws/link → outside；經 symlink 讀 outside 的檔案 → 解析後不在 ws 下 → 拒（I5）
        let ws = tmp.appendingPathComponent("ws")
        let outside = tmp.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: ws, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try "secret".write(to: outside.appendingPathComponent("secret.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: ws.appendingPathComponent("link"),
                                                   withDestinationURL: outside)
        let allowlist = PathAllowlist(allowedRoots: [ws.path])
        XCTAssertFalse(allowlist.permits(ws.path + "/link/secret.txt"))
        XCTAssertTrue(allowlist.permits(ws.path + "/normal.txt"))
    }

    func testSecretComponentsDeniedEvenInsideRoot() {
        let allowlist = PathAllowlist(allowedRoots: [tmp.path])
        XCTAssertFalse(allowlist.permits(tmp.path + "/.ssh/id_rsa"))       // root 內也拒秘密元件
        XCTAssertFalse(allowlist.permits(tmp.path + "/config/prod.env"))
        XCTAssertFalse(allowlist.permits("~/.ssh/id_rsa"))                 // ~ 展開後不在 root
    }

    // MARK: sbpl（B4）

    func testSbplDeniesNetworkByDefault() throws {
        let profile = try SbplProfileBuilder().profile(execAllowlist: ["/bin/ls"],
                                                       workspace: "/ws", deniedSubpaths: ["/Users/x/.ssh"])
        let lines = profile.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines[1], "(deny default)")                     // deny-default 先行
        XCTAssertTrue(lines.contains("(deny network*)"))
        XCTAssertFalse(profile.contains("(allow network"))
    }

    func testSbplExecAllowlistOnly() throws {
        let profile = try SbplProfileBuilder().profile(execAllowlist: ["/bin/ls", "/usr/bin/git"],
                                                       workspace: "/ws", deniedSubpaths: [])
        XCTAssertTrue(profile.contains("(allow process-exec (literal \"/bin/ls\") (literal \"/usr/bin/git\"))"))
        XCTAssertTrue(profile.contains("(allow file-write* (subpath \"/ws\"))"))
    }

    // MARK: sbpl 路徑安全（第 ③ 段 (c)）

    /// **核心**：路徑裡的引號不可以提前結束字面值。
    ///
    /// 這是把「一個檔名」變成「一條 profile 規則」的路徑。若跳脫失效，
    /// 一個名為 `/ws") (allow default) (deny nothing "` 的目錄就能讓整道沙箱失效，
    /// 而產出的 profile 看起來仍然像個正常的 profile。
    func testQuoteInPathCannotInjectRules() throws {
        let nasty = "/ws\") (allow default) (deny nothing \""
        let profile = try SbplProfileBuilder().profile(execAllowlist: [],
                                                       workspace: nasty, deniedSubpaths: [])
        let line = try XCTUnwrap(profile.split(separator: "\n").first { $0.contains("file-read*") })

        // ⚠️ 不可以斷言「profile 不含 (allow default) 這幾個字」——那條斷言是錯的：
        // 那段文字本來就是路徑的**內容**，跳脫不會讓它消失，它只是待在字面值裡面。
        // 該驗的是**字面值有沒有提前結束**：把被跳脫的引號拿掉之後，
        // 整行應該只剩下兩個引號，也就是 (subpath "…") 的那對定界符。
        // 若跳脫失效，路徑裡的引號會多出來，後面的內容就脫離字串變成 profile 指令。
        let withoutEscapedQuotes = line.replacingOccurrences(of: "\\\"", with: "")
        XCTAssertEqual(withoutEscapedQuotes.filter { $0 == "\"" }.count, 2,
                       "字面值提前結束了，路徑內容脫離字串：\(line)")
    }

    /// 反斜線要先跳脫。順序反了的話 `\` 結尾的路徑會把後面的引號吃掉。
    func testBackslashIsEscapedBeforeQuote() {
        XCTAssertEqual(SbplProfileBuilder.quoted("/a\\b"), "\"/a\\\\b\"")
        XCTAssertEqual(SbplProfileBuilder.quoted("/a\\"), "\"/a\\\\\"")
    }

    /// 控制字元（含換行）無法在 profile 裡安全表達——**拒絕，不要盡力表達**。
    func testControlCharactersAreRejected() {
        for bad in ["/ws\n(allow default)", "/ws\u{0}", "/ws\t"] {
            XCTAssertThrowsError(try SbplProfileBuilder.sanitize(bad), "應拒絕：\(bad)")
        }
    }

    /// 相對路徑的意義取決於當下工作目錄——放進沙箱規則裡是不可預測的。
    func testRelativePathIsRejected() {
        XCTAssertThrowsError(try SbplProfileBuilder.sanitize("ws/sub"))
        XCTAssertThrowsError(try SbplProfileBuilder.sanitize(""))
    }

    /// 結尾斜線會讓 `(subpath …)` 規則**安靜地不生效**，所以一律去掉。根目錄除外。
    func testTrailingSlashIsStripped() throws {
        XCTAssertEqual(try SbplProfileBuilder.sanitize("/a/b/"), "/a/b")
        XCTAssertEqual(try SbplProfileBuilder.sanitize("/a/b///"), "/a/b")
        XCTAssertEqual(try SbplProfileBuilder.sanitize("/"), "/")
    }

    /// 一條路徑不安全就整個 profile 失敗——**不可以只跳過壞的那條**。
    /// 少一條 deny 的 profile 看起來完全正常，但防線已經有洞。
    func testOneBadPathFailsTheWholeProfile() {
        XCTAssertThrowsError(
            try SbplProfileBuilder().profile(execAllowlist: [],
                                             workspace: "/ws",
                                             deniedSubpaths: ["/Users/x/.ssh", "relative/bad"]))
    }

    /// runtime 最小讀取集合預設要在——沒有它，`(deny default)` 下任何程式都起不來，
    /// 於是所有負向測試都會「通過」，但那只證明了什麼都動不了。
    func testRuntimeMinimumIsIncludedByDefault() throws {
        let profile = try SbplProfileBuilder().profile(
            execAllowlist: ["/bin/cat"], workspace: "/ws", deniedSubpaths: [])
        for runtime in SbplProfileBuilder.runtimeReadSubpaths {
            XCTAssertTrue(profile.contains("(allow file-read* (subpath \"\(runtime)\"))"),
                          "缺少 runtime 讀取路徑：\(runtime)")
        }
    }

    /// runtime 路徑一律是**絕對路徑**且通得過 sanitize——這組是寫死在原始碼裡的，
    /// 打錯字不會有人發現，profile 照樣產得出來、只是那條規則永遠不匹配。
    func testRuntimePathsAreWellFormed() throws {
        for runtime in SbplProfileBuilder.runtimeReadSubpaths {
            XCTAssertEqual(try SbplProfileBuilder.sanitize(runtime), runtime,
                           "runtime 路徑本身就該是正規化後的形式：\(runtime)")
        }
    }

    /// runtime 的額外規則也要跟著 includeRuntimeMinimum 一起開關，
    /// 否則對照實驗會測到一個「半套」的 profile，得出的結論不對應任何真實設定。
    func testRuntimeExtraRulesFollowTheSameSwitch() throws {
        let withMinimum = try SbplProfileBuilder().profile(
            execAllowlist: [], workspace: "/ws", deniedSubpaths: [])
        let without = try SbplProfileBuilder().profile(
            execAllowlist: [], workspace: "/ws", deniedSubpaths: [], includeRuntimeMinimum: false)
        for rule in SbplProfileBuilder.runtimeExtraRules {
            XCTAssertTrue(withMinimum.contains(rule), "缺少：\(rule)")
            XCTAssertFalse(without.contains(rule), "關掉時不該還在：\(rule)")
        }
    }

    /// sysctl **逐項具名**，不可開放整個 sysctl-read——後者會洩漏一堆系統狀態，
    /// 而我們只需要 libSystem 起始化用到的那兩個。
    func testSysctlIsNamedNotWideOpen() throws {
        let profile = try SbplProfileBuilder().profile(
            execAllowlist: [], workspace: "/ws", deniedSubpaths: [])
        XCTAssertTrue(profile.contains("(sysctl-name \"kern.bootargs\")"))
        XCTAssertFalse(profile.contains("(allow sysctl-read)"),
                       "不可無條件開放 sysctl-read")
    }

    // MARK: sbpl 符號連結解析（真機 dogfood 抓到）

    /// **profile 裡的路徑必須是解過符號連結的**。
    ///
    /// 真機日誌：工作目錄給 `/tmp/…`，核心卻拿 `/private/tmp/…` 在比對，
    /// 於是 `(subpath "/tmp/…")` **永遠不匹配**——而 profile 看起來完全正常。
    /// macOS 的 /tmp、/var、/etc 都是符號連結，這不是邊角案例。
    func testPathsAreSymlinkResolvedBeforeEmitting() throws {
        let builder = SbplProfileBuilder(resolvePath: { path in
            path.hasPrefix("/tmp/") ? "/private" + path : path
        })
        let profile = try builder.profile(execAllowlist: [],
                                          workspace: "/tmp/ws",
                                          deniedSubpaths: ["/tmp/ws/.secrets"])
        XCTAssertTrue(profile.contains("(subpath \"/private/tmp/ws\")"), "實際：\(profile)")
        XCTAssertTrue(profile.contains("(subpath \"/private/tmp/ws/.secrets\")"))
        XCTAssertFalse(profile.contains("(subpath \"/tmp/ws\")"),
                       "未解析的路徑不可出現——那條規則永遠不會匹配")
    }

    /// 真的解析器在 macOS 上要把 /tmp 解成 /private/tmp。
    ///
    /// 這條會碰檔案系統，但它守的正是「預設值真的有效」——注入假的測完，
    /// 若預設值其實沒作用，上一條會綠、真機仍然壞。**這條真的抓到過**：
    /// 原本用 `URL.resolvingSymlinksInPath()`，而 Foundation 會把 `/private` 前綴
    /// 再拿掉，等於白解析一場。改用 `realpath(3)`。
    func testSystemResolverResolvesTmp() {
        XCTAssertEqual(SbplProfileBuilder.systemPathResolver("/tmp"), "/private/tmp")
    }

    /// 路徑不存在時退回原值，不可炸掉整個 profile 的產生。
    func testSystemResolverFallsBackForMissingPath() {
        let missing = "/definitely-not-a-real-path-\(UUID().uuidString)"
        XCTAssertEqual(SbplProfileBuilder.systemPathResolver(missing), missing)
    }

    /// 解析後仍要通過 sanitize——解析器可能吐出結尾斜線之類的東西。
    func testResolvedPathIsStillSanitized() throws {
        let builder = SbplProfileBuilder(resolvePath: { _ in "/private/tmp/ws/" })
        let profile = try builder.profile(execAllowlist: [], workspace: "/tmp/ws", deniedSubpaths: [])
        XCTAssertTrue(profile.contains("(subpath \"/private/tmp/ws\")"))
        XCTAssertFalse(profile.contains("ws/\""), "結尾斜線應已去掉")
    }

    /// **這條守住整個放寬的前提**：全域 `(allow file-read-metadata)` 之下，
    /// 秘密路徑的 deny 仍然必須勝出。
    ///
    /// sbpl 是最後一條相符的規則勝出，所以 deny 排在後面就蓋得過全域 allow。
    /// 若哪天有人為了「整理」把 allow 移到最後，秘密路徑會安靜地變成可讀——
    /// 而 profile 看起來完全正常。
    func testSecretDenyOverridesGlobalMetadataAllow() throws {
        let profile = try SbplProfileBuilder().profile(
            execAllowlist: [], workspace: "/ws", deniedSubpaths: ["/ws/.secrets"])
        let lines = profile.split(separator: "\n").map(String.init)
        let metadataAllow = try XCTUnwrap(lines.firstIndex(of: "(allow file-read-metadata)"))
        let secretDeny = try XCTUnwrap(
            lines.firstIndex { $0.contains("(deny file-read* (subpath \"/ws/.secrets\"))") })
        XCTAssertLessThan(metadataAllow, secretDeny,
                          "全域 metadata allow 排在秘密 deny 之後的話，秘密路徑會變成可讀")
    }

    /// exec 白名單的每個項目都要自動附帶「可讀該檔」——**能 exec 不等於能讀**，
    /// 載入器讀不到 binary 本身就起不來（真機日誌：deny file-read-data /bin/cat）。
    func testExecAllowlistImpliesReadAccess() throws {
        let profile = try SbplProfileBuilder().profile(
            execAllowlist: ["/bin/cat", "/usr/bin/touch"], workspace: "/ws", deniedSubpaths: [])
        XCTAssertTrue(profile.contains("(allow file-read* (literal \"/bin/cat\") (literal \"/usr/bin/touch\"))"))
        // 以及所在目錄（去重、排序，避免同目錄的多個工具產生重複規則）
        XCTAssertTrue(profile.contains("(allow file-read-data (literal \"/bin\") (literal \"/usr/bin\"))"),
                      "實際：\(profile)")
    }

    /// 同目錄的多個工具不該產生重複的父目錄規則。
    func testExecParentDirectoriesAreDeduplicated() throws {
        let profile = try SbplProfileBuilder().profile(
            execAllowlist: ["/bin/cat", "/bin/echo"], workspace: "/ws", deniedSubpaths: [])
        let occurrences = profile.components(separatedBy: "(literal \"/bin\")").count - 1
        XCTAssertEqual(occurrences, 1, "父目錄 /bin 只該出現一次")
    }

    /// 根目錄只給 `literal`，不可寫成 `(subpath "/")`——那等於把整台機器打開，
    /// 而且它看起來只是「多放一條讀取規則」。
    func testRootIsLiteralNotSubpath() throws {
        let profile = try SbplProfileBuilder().profile(
            execAllowlist: [], workspace: "/ws", deniedSubpaths: [])
        XCTAssertTrue(profile.contains("(allow file-read-data (literal \"/\"))"))
        XCTAssertFalse(profile.contains("(subpath \"/\")"), "根目錄不可用 subpath")
    }

    /// 可以關掉——驗證腳本要用它做對照實驗：關掉之後正向案例應該連跑都跑不起來。
    /// 若關掉仍跑得起來，代表這組路徑是多餘的，該拿掉（寧可少放）。
    func testRuntimeMinimumCanBeDisabledForControlExperiment() throws {
        let profile = try SbplProfileBuilder().profile(
            execAllowlist: ["/bin/cat"], workspace: "/ws", deniedSubpaths: [],
            includeRuntimeMinimum: false)
        XCTAssertFalse(profile.contains("/usr/lib"))
        XCTAssertTrue(profile.contains("(allow file-read* (subpath \"/ws\"))"),
                      "關掉 runtime 最小集合不該影響工作目錄規則")
    }

    /// runtime 的**子路徑**一律只給讀。寫入權限只在工作目錄，以及
    /// `/dev/dtracehelper` 這個逐一具名的例外（它是讀寫開啟的裝置節點）。
    func testRuntimeSubpathsAreReadOnly() throws {
        let profile = try SbplProfileBuilder().profile(
            execAllowlist: [], workspace: "/ws", deniedSubpaths: [])
        for runtime in SbplProfileBuilder.runtimeReadSubpaths {
            XCTAssertFalse(profile.contains("(allow file-write* (subpath \"\(runtime)\"))"),
                           "\(runtime) 不該可寫")
        }
    }

    /// 唯一的寫入例外必須是**具名的單一檔案**，不可是子路徑。
    /// 真機日誌顯示 /dev/dtracehelper 是讀寫開啟的；只放讀那一半的症狀跟完全沒放一樣，
    /// 但 profile 裡看起來「已經處理過了」。
    func testOnlyDtracehelperIsWritableOutsideWorkspace() throws {
        let profile = try SbplProfileBuilder().profile(
            execAllowlist: [], workspace: "/ws", deniedSubpaths: [])
        let writes = profile.split(separator: "\n").filter { $0.contains("allow file-write") }
        XCTAssertEqual(writes.count, 2, "工作目錄 + dtracehelper，就這兩條：\(writes)")
        XCTAssertTrue(writes.contains { $0.contains("(subpath \"/ws\")") })
        XCTAssertTrue(writes.contains { $0.contains("(literal \"/dev/dtracehelper\")") })
    }

    /// `closedRoots` 必須排在工作目錄 allow **之前**，工作目錄才開得回來。
    ///
    /// 順序反了的後果不是「太鬆」而是「太緊」——工作目錄變成不可讀，
    /// 所有動作都失敗，而 profile 看起來完全合理。
    func testClosedRootsComeBeforeWorkspaceAllow() throws {
        let profile = try SbplProfileBuilder().profile(
            execAllowlist: [], workspace: "/home/u/ws", deniedSubpaths: [],
            closedRoots: ["/home/u"])
        let lines = profile.split(separator: "\n").map(String.init)
        let closed = try XCTUnwrap(lines.firstIndex { $0 == #"(deny file-read* (subpath "/home/u"))"# })
        let allow = try XCTUnwrap(lines.firstIndex { $0 == #"(allow file-read* (subpath "/home/u/ws"))"# })
        XCTAssertLessThan(closed, allow, "家目錄關閉必須在工作目錄開啟之前")
    }

    /// 三層順序完整檢查：關家目錄 → 開工作目錄 → 關秘密路徑。
    /// 這三層的相對位置就是整個 profile 的安全語意，值得單獨釘住。
    func testThreeLayerOrderingIsPreserved() throws {
        let profile = try SbplProfileBuilder().profile(
            execAllowlist: [], workspace: "/home/u/ws",
            deniedSubpaths: ["/home/u/.ssh"], closedRoots: ["/home/u"])
        let lines = profile.split(separator: "\n").map(String.init)
        func index(_ needle: String) throws -> Int {
            try XCTUnwrap(lines.firstIndex { $0.contains(needle) })
        }
        let closed = try index(#"(deny file-read* (subpath "/home/u"))"#)
        let allow = try index(#"(allow file-read* (subpath "/home/u/ws"))"#)
        let secret = try index(#"(deny file-read* (subpath "/home/u/.ssh"))"#)
        XCTAssertTrue(closed < allow && allow < secret,
                      "順序應為 關家目錄(\(closed)) → 開工作目錄(\(allow)) → 關秘密(\(secret))")
    }

    /// **deny 必須排在 allow 之後**：sbpl 是最後一條相符的規則勝出。
    /// 順序顛倒的話，「秘密路徑就在工作目錄底下」這個最重要的情況會被 allow 蓋過去。
    func testDenyRulesComeAfterAllowRules() throws {
        let profile = try SbplProfileBuilder().profile(
            execAllowlist: [], workspace: "/ws", deniedSubpaths: ["/ws/.ssh"])
        let lines = profile.split(separator: "\n").map(String.init)
        let allowIndex = try XCTUnwrap(lines.firstIndex { $0.contains("(allow file-read* (subpath \"/ws\"))") })
        let denyIndex = try XCTUnwrap(lines.firstIndex { $0.contains("(deny file-read* (subpath \"/ws/.ssh\"))") })
        XCTAssertLessThan(allowIndex, denyIndex,
                          "deny 排在 allow 之前的話，工作目錄底下的秘密路徑會變成可讀")
    }

    // MARK: 速率 / 迴圈（I8）

    func testRateLimitHaltsAfterN() async {
        var (model, executor) = makeStack(limiter: RateLimiter(maxActionsPerWindow: 3, window: 60))
        model.begin()
        for i in 0..<3 {                                                // 3 個不同動作 OK
            let a = ProposedAction(kind: .click(x: i, y: i))
            let t = approvedToken(&model, for: a)
            try? await executor.execute(a, token: t)
        }
        let a4 = ProposedAction(kind: .click(x: 99, y: 99))
        let t4 = approvedToken(&model, for: a4)
        await expectError(.rateLimited) { try await executor.execute(a4, token: t4) }
    }

    func testSameActionLoopHalts() async {
        var (model, executor) = makeStack(limiter: RateLimiter(maxActionsPerWindow: 100, loopThreshold: 3))
        model.begin()
        for _ in 0..<3 {                                                // 同座標連點 3 次 OK
            let a = ProposedAction(kind: .click(x: 5, y: 5))
            let t = approvedToken(&model, for: a)
            try? await executor.execute(a, token: t)
        }
        let a4 = ProposedAction(kind: .click(x: 5, y: 5))               // 第 4 次相同 → halt
        let t4 = approvedToken(&model, for: a4)
        await expectError(.loopDetected) { try await executor.execute(a4, token: t4) }
    }

    // MARK: 稽核（I9）+ 真執行佔位

    func testAuditLogPerExecution() async throws {
        var (model, executor) = makeStack()
        model.begin()
        let a1 = ProposedAction(kind: .screenshot)
        try await executor.execute(a1, token: approvedToken(&model, for: a1))
        let a2 = ProposedAction(kind: .typeText("hi"))
        try await executor.execute(a2, token: approvedToken(&model, for: a2))
        let log = await executor.auditLog
        // 每次執行留兩筆：嘗試 + 結果。
        XCTAssertEqual(log, ["attempt screenshot", "executed screenshot",
                             "attempt type(2 chars)", "executed type(2 chars)"])
    }

    /// 稽核不可把「沒執行成功」記成執行過（I9）。
    ///
    /// step 53.1 之後這條特別重要：XPC service 會**例行地**回「收到但沒做」，
    /// 若稽核只留一筆 "execute …"，紀錄上會顯示執行過、實際上什麼都沒發生。
    func testAuditLogDistinguishesAttemptFromExecution() async {
        var (model, executor) = makeStack(performer: { _ in throw ExecutionError.notWired })
        model.begin()
        let a = ProposedAction(kind: .screenshot)
        let token = approvedToken(&model, for: a)        // 先取 token，避免在 async 閉包裡改 model
        await expectError(.notWired) { try await executor.execute(a, token: token) }
        let log = await executor.auditLog
        XCTAssertEqual(log.first, "attempt screenshot")
        XCTAssertEqual(log.count, 2)
        XCTAssertTrue(log[1].hasPrefix("notExecuted screenshot"), "實際內容：\(log[1])")
        XCTAssertFalse(log.contains { $0.hasPrefix("executed ") }, "沒執行就不可記成 executed")
    }

    /// 被閘門擋下來的動作**也要留紀錄**（I9：無論核准與否）。
    ///
    /// 這六條正好是最需要事後查得到的情況。稽核只記成功的話，
    /// 「一切正常」與「有人一直被擋」在紀錄上會長得一模一樣。
    func testBlockedActionsAreAudited() async {
        var (model, executor) = makeStack(
            policy: SandboxPolicy(allowedTools: ["computer"]))   // 不含 bash → shell 會被擋
        model.begin()
        let a = ProposedAction(kind: .shell(argv: ["ls"]))
        let token = approvedToken(&model, for: a)
        await expectError(.toolNotAllowed("shell(ls)")) {
            try await executor.execute(a, token: token)
        }
        let log = await executor.auditLog
        XCTAssertEqual(log.count, 1, "被擋也要留一筆：\(log)")
        XCTAssertTrue(log[0].hasPrefix("blocked shell(ls)"), "實際內容：\(log[0])")
        XCTAssertFalse(log.contains { $0.hasPrefix("attempt ") }, "沒通過閘門就不算嘗試執行")
    }

    /// 作廢的 token 是最該留痕的一種——代表有人拿失效的核准來執行。
    func testStaleTokenIsAudited() async {
        var (model, executor) = makeStack()
        model.begin()
        let a = ProposedAction(kind: .screenshot)
        let token = approvedToken(&model, for: a)
        model.stop()                                    // 世代作廢（I7）
        await expectError(.staleToken) { try await executor.execute(a, token: token) }
        let log = await executor.auditLog
        XCTAssertEqual(log.count, 1)
        XCTAssertTrue(log[0].contains("世代已作廢"), "實際內容：\(log[0])")
    }

    /// performer 未接線時同樣不可記成執行過。
    func testAuditLogHonestWhenPerformerMissing() async {
        var (model, executor) = makeStack(performer: nil)
        model.begin()
        let a = ProposedAction(kind: .screenshot)
        let token = approvedToken(&model, for: a)
        await expectError(.notWired) { try await executor.execute(a, token: token) }
        let log = await executor.auditLog
        XCTAssertFalse(log.contains { $0.hasPrefix("executed ") })
    }

    func testNotWiredWithoutPerformer() async {
        var (model, executor) = makeStack(performer: nil)               // 真執行 🔒 step 53
        model.begin()
        let a = ProposedAction(kind: .screenshot)
        let t = approvedToken(&model, for: a)
        await expectError(.notWired) { try await executor.execute(a, token: t) }
    }
}
