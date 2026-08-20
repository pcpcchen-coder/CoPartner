import Foundation
// 設計：sandbox-threat-model.md §6（sbpl profile）+ B4。deny-default、network 全拒（T5）、
// exec 白名單逐工具開、寫入限工作目錄、秘密路徑加倍拒。
// 此檔只產 profile 字串（CI 可測）；真 sandbox-exec / posix_spawn 套用 🔒 第 ③④ 段。
//
// ⚠️ **這個檔產出的是安全設定，不是顯示字串。** 一個被污染的路徑若能改變 profile 的結構，
// 整道沙箱就等於不存在——所以路徑一律先驗證、再正規化、再跳脫，三關都不過就 throw。
// 現在還沒有呼叫端會把模型提議的路徑餵進來，但第 ④ 段接上執行之後就可能，
// 那時再補就太晚：注入面要在有東西可注入之前就封起來。

public enum SbplProfileError: Error, Equatable {
    /// 相對路徑無法安全地放進 `(subpath …)`——它的意義取決於當下工作目錄。
    case pathNotAbsolute(String)
    /// 含換行 / NUL / 其他控制字元。這種路徑在 profile 裡無法表達，
    /// 而「盡力表達」正是注入的來源。
    case pathContainsControlCharacter(String)
    case emptyPath
}

public struct SbplProfileBuilder: Sendable {
    /// 路徑 → 解開符號連結後的真實路徑。
    ///
    /// 可注入的理由是**測試決定性**：真的解析要碰檔案系統，那會讓測試依賴執行環境。
    /// 預設用真的解析器，測試注入假的。
    public typealias PathResolver = @Sendable (String) -> String

    /// 真的符號連結解析。
    ///
    /// ⚠️ **不要用 `URL.resolvingSymlinksInPath()`**：它會把 `/private` 前綴再拿掉
    /// （Foundation 刻意的「標準化」行為），等於把我們要的解析結果又還原回去——
    /// `/tmp` 解成 `/private/tmp` 之後又變回 `/tmp`，白忙一場而且沒有任何跡象。
    ///
    /// `realpath(3)` 才是核心在比對的那個答案。路徑不存在時回 NULL，
    /// 此時退回原值（產生的規則不會匹配，但那是「路徑不存在」的正常後果）。
    public static let systemPathResolver: PathResolver = { path in
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    private let resolvePath: PathResolver
    public init(resolvePath: @escaping PathResolver = SbplProfileBuilder.systemPathResolver) {
        self.resolvePath = resolvePath
    }

    /// 產生 profile。任何一個路徑不安全就整個失敗——**不做「跳過壞的那條」**：
    /// 少一條 deny 規則的 profile 看起來仍然正常，但防線已經有洞。
    /// 讓白名單內的工具**能夠啟動**所需的最小讀取集合。
    ///
    /// `(deny default)` 之下，被 exec 的程式連 dyld 與共用快取都讀不到，
    /// 於是**任何東西都跑不起來**。這一組不是「放寬」，是「讓正向測試有機會通過」——
    /// 沒有它，所有負向測試都會通過，但那只證明了「什麼都動不了」，
    /// 證明不了 profile 有在擋對的東西。
    ///
    /// ⚠️ **這一版是依慣例猜的，尚未在真機驗證。** `scripts/sandbox-verify.sh`
    /// 的正向測試就是要逐條確認：少了哪一條會讓 `/bin/cat` 起不來。
    /// 原則是**寧可少放**——正向測試失敗看得見，多放的權限看不見。
    /// 只在正向測試證明必要時才加，不要為了「看起來會動」預先放寬。
    public static let runtimeReadSubpaths = [
        "/usr/lib",           // dyld 本體、系統 dylib
        "/System/Library",    // 框架
        "/private/var/db/dyld",   // 舊版 dyld 共用快取位置
        // macOS 13 之後 dyld 共用快取搬進 Cryptex。
        // （第二輪的假設；實測後確認**不是**啟動失敗的原因，但保留——它是快取的真實位置。）
        "/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld",
    ]

    /// 不是「某個子路徑可讀」形狀的 runtime 規則。
    ///
    /// **每一條都對應一則真機統一日誌裡的拒絕紀錄**，不是憑印象加的。
    /// 這個區別很重要：沙箱規則多放一條看不見代價，所以每一條都要說得出
    /// 「哪一次執行、哪一行日誌」要求了它。
    public static let runtimeExtraRules = [
        // libSystem / 語系起始化讀的 sysctl。**逐項具名**而不是開放整個 sysctl-read——
        // 後者會洩漏一堆系統狀態，而我們只需要這幾個。清單來自兩輪真機日誌：
        //   deny(1) sysctl-read kern.bootargs / security.mac.lockdown_mode_state
        //   deny(1) sysctl-read kern.osvariant_status / hw.ephemeral_storage
        //   deny(1) sysctl-read kern.osproductversion / kern.iossupportversion
        "(allow sysctl-read "
            + "(sysctl-name \"kern.bootargs\") "
            + "(sysctl-name \"security.mac.lockdown_mode_state\") "
            + "(sysctl-name \"kern.osvariant_status\") "
            + "(sysctl-name \"hw.ephemeral_storage\") "
            + "(sysctl-name \"kern.osproductversion\") "
            + "(sysctl-name \"kern.iossupportversion\"))",
        // Sandbox: cat(…) deny(1) file-read-data /
        // 路徑解析要讀根目錄本身。**只給根目錄這一個 literal**，
        // 不是 (subpath "/")——那等於把整台機器打開。
        "(allow file-read-data (literal \"/\"))",
        // ⚠️ 這一條是**刻意的放寬**，值得單獨說明。
        //
        // 真機日誌顯示路徑解析會對一長串祖先目錄要 metadata：
        //   deny(1) file-read-metadata /var  /tmp  /usr/share/locale/zh_TW.UTF-8/LC_CTYPE
        // 逐條補是補不完的——`/tmp` 是 `/private/tmp` 的符號連結、語系檔位置隨地區變，
        // 而每漏一條的症狀都是「動作莫名其妙失敗」。
        //
        // 取捨：**metadata 不是內容**。它洩漏的是「這個路徑存不存在、多大」，
        // 不是檔案裡寫什麼。威脅模型要擋的是秘密**內容**外洩與破壞性寫入，
        // 兩者都不受這條影響。
        //
        // 而且秘密路徑仍然完全受保護：deny 規則用的是 `file-read*`（含 metadata）
        // 且**排在最後**——最後一條相符的規則勝出，所以它蓋得過這條。
        // `testSecretDenyOverridesGlobalMetadataAllow` 釘住這個關係。
        "(allow file-read-metadata)",
        // 每個程序啟動時都會開的東西。真機日誌先出現 read、放行後又出現 write：
        //   deny(1) file-read-data /dev/dtracehelper
        //   deny(1) file-write-data /dev/dtracehelper
        // 它是**讀寫**開啟的。只放讀那一半的症狀跟完全沒放一樣——程式照樣起不來，
        // 但 profile 裡看起來「已經處理過 dtracehelper 了」。
        "(allow file-read* (literal \"/dev/dtracehelper\"))",
        "(allow file-write* (literal \"/dev/dtracehelper\"))",
        // 語系資料要讀**內容**，不只 metadata（deny file-read-data /usr/share/locale/C.UTF-8/LC_CTYPE）。
        // 給整個 locale 目錄而非逐一列舉：語系檔會隨系統地區設定變，逐條補補不完，
        // 而它們是唯讀的公開系統資料，放寬的代價很小。
        "(allow file-read* (subpath \"/usr/share/locale\"))",
        // Cryptex 掛載點本身要讀得到（deny file-read-data /System/Volumes/Preboot/Cryptexes/OS）。
        "(allow file-read* (subpath \"/System/Volumes/Preboot/Cryptexes/OS\"))",
    ]

    /// - Parameters:
    ///   - closedRoots: 在**工作目錄規則之前**關掉的整片區域（通常是家目錄）。
    ///     順序是重點：`closedRoots` → 工作目錄 allow → `deniedSubpaths` deny，
    ///     最後一條相符的規則勝出，所以工作目錄仍開得回來、秘密仍關得掉。
    ///     這一層存在的理由見 `SandboxWorkspace` 對 metadata 列舉的說明。
    ///   - deniedSubpaths: 在所有 allow **之後**關掉的路徑（秘密目錄）。
    public func profile(execAllowlist: [String],
                        workspace: String,
                        deniedSubpaths: [String],
                        closedRoots: [String] = [],
                        includeRuntimeMinimum: Bool = true) throws -> String {
        // ⚠️ **先解符號連結再寫進 profile**。真機日誌：
        //   deny(1) file-read-data /private/tmp/…/hello.txt
        // 工作目錄給的是 `/tmp/…`，但核心是拿**正規化後**的 `/private/tmp/…` 在比對，
        // 所以 `(subpath "/tmp/…")` 那條規則**永遠不匹配**——而它看起來完全正常。
        // macOS 的 /tmp、/var、/etc 都是符號連結，這不是邊角案例。
        //
        // 威脅模型 I5 早就要求「路徑正規化 + symlink 解析後再比對白名單」；
        // `PathAllowlist` 做了，profile 這邊漏了。同一條不變式要在兩個地方各自成立。
        let workspacePath = try Self.sanitize(resolvePath(workspace))
        let execPaths = try execAllowlist.map { try Self.sanitize(resolvePath($0)) }
        let deniedPaths = try deniedSubpaths.map { try Self.sanitize(resolvePath($0)) }
        let closedPaths = try closedRoots.map { try Self.sanitize(resolvePath($0)) }

        var lines = [
            "(version 1)",
            "(deny default)",           // deny-default：一切先拒再逐項開
            "(deny network*)",          // 沙箱內一律斷網（T5 外洩）
        ]
        if !execPaths.isEmpty {
            let literals = execPaths.map { "(literal \(Self.quoted($0)))" }.joined(separator: " ")
            lines.append("(allow process-exec \(literals))")
            // 真機日誌：`deny(1) file-read-data /bin/cat` 與 `deny(1) file-read-data /bin`。
            // **能 exec 不等於能讀**——載入器要讀得到 binary 本身，以及它所在的目錄。
            // 這兩條因此綁在 exec 白名單上自動產生，而不是另外維護一份清單：
            // 兩份清單遲早會不同步，而不同步的症狀是「某個工具就是跑不起來」。
            lines.append("(allow file-read* \(literals))")
            let parents = Set(execPaths.map { ($0 as NSString).deletingLastPathComponent })
                .sorted()
                .map { "(literal \(Self.quoted($0)))" }
                .joined(separator: " ")
            if !parents.isEmpty {
                lines.append("(allow file-read-data \(parents))")
            }
        }
        if includeRuntimeMinimum {
            // 放在工作目錄規則之前：它們彼此不重疊，順序不影響結果，
            // 但擺前面能讓「哪些是為了讓程式跑起來、哪些是任務所需」在 profile 裡一眼分得出來。
            for runtime in Self.runtimeReadSubpaths {
                lines.append("(allow file-read* (subpath \(Self.quoted(runtime))))")
            }
            lines.append(contentsOf: Self.runtimeExtraRules)
        }
        // ⚠️ 這一層要排在工作目錄規則**之前**。
        //
        // 全域 `(allow file-read-metadata)` 是為了路徑解析而放寬的，但它與 exec 白名單裡的
        // `find` / `grep` 相乘之後，語意就從「偶爾解析一個路徑」變成「可以掃整台機器」——
        // `find ~ -name "*.key"` 列得出來。那是完全不同的量級。
        //
        // 所以把家目錄整片關掉（含 metadata），再把工作目錄開回來。
        // /usr、/System 之類的系統路徑仍可列舉，但那些是公開的。
        for closed in closedPaths {
            lines.append("(deny file-read* (subpath \(Self.quoted(closed))))")
            lines.append("(deny file-write* (subpath \(Self.quoted(closed))))")
        }
        lines.append("(allow file-read* (subpath \(Self.quoted(workspacePath))))")
        lines.append("(allow file-write* (subpath \(Self.quoted(workspacePath))))")
        // ⚠️ **deny 必須排在 allow 之後**。sbpl 是最後一條相符的規則勝出，
        // 順序顛倒的話「秘密路徑在工作目錄底下」這個最重要的情況會被 allow 蓋過去。
        // 這個先後關係由 testDenyRulesComeAfterAllowRules 釘住。
        // （🔒「最後一條勝出」是 sbpl 的既定語意，但本專案尚未在真機上實測過——
        //   第 ③ 段的成對測試要**專門驗這一條**：把秘密路徑放進工作目錄底下，確認讀不到。）
        for denied in deniedPaths {
            lines.append("(deny file-read* (subpath \(Self.quoted(denied))))")
            lines.append("(deny file-write* (subpath \(Self.quoted(denied))))")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - 路徑安全

    /// 驗證 + 正規化。回傳可安全放進 profile 的絕對路徑。
    public static func sanitize(_ path: String) throws -> String {
        guard !path.isEmpty else { throw SbplProfileError.emptyPath }
        guard !path.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else {
            throw SbplProfileError.pathContainsControlCharacter(path)
        }
        guard path.hasPrefix("/") else { throw SbplProfileError.pathNotAbsolute(path) }
        // 去掉結尾斜線：`(subpath "/a/b/")` 與 `(subpath "/a/b")` 在 sandbox 裡不等價，
        // 前者可能整條規則失效——而失效的方式是「安靜地不擋」。根目錄除外。
        var trimmed = path
        while trimmed.count > 1, trimmed.hasSuffix("/") { trimmed.removeLast() }
        return trimmed
    }

    /// 包成 sbpl 字串字面值。
    ///
    /// 反斜線**必須先跳脫**，否則後跳脫的引號所產生的反斜線會被二次處理。
    /// 這個順序錯了的後果不是格式難看，是路徑裡的 `"` 能提前結束字面值、
    /// 讓後面的內容變成 profile 指令——也就是把一個檔名變成一條規則。
    public static func quoted(_ path: String) -> String {
        let escaped = path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
