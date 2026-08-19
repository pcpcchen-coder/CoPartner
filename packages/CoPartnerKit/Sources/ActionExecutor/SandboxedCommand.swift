import Foundation
// 設計：sandbox-threat-model.md B4 + I4（無 shell 字串通道）。第 ④ 段的**純值部分**。
//
// 這個檔把「要怎麼執行」變成一個可檢查的值：完整的 argv、profile 檔位置、逾時。
// 真正的 `posix_spawn` 在 XPC service 裡（🔒 盲寫），但**組出來的東西長什麼樣**
// 完全在這裡決定，因此完全可以在 CI 驗。
//
// 這樣切的理由跟前幾段一樣：平台呼叫測不到，但「餵給平台呼叫的參數」測得到，
// 而後者才是安全性所在——`posix_spawn` 本身不會出錯，錯的是我們給它什麼。

public enum SandboxedCommandError: Error, Equatable {
    case emptyArgv
    /// 相對路徑會經由 PATH 解析，實際執行到什麼取決於環境變數——
    /// 那正好是沙箱要消滅的不確定性。而且 profile 的 exec 白名單是用絕對路徑比對的，
    /// 相對路徑必然對不上（症狀是「莫名其妙被擋」）。
    case commandNotAbsolute(String)
    case profilePathNotAbsolute(String)
}

/// 一次沙箱執行的完整描述。
public struct SandboxedCommand: Sendable, Equatable {
    /// 沙箱啟動器。用 `-f <檔案>` 而不是 `-p <內嵌字串>`：
    /// profile 有數十行，塞進命令列除了難讀，還可能撞上長度上限；
    /// 而且命令列上的東西會出現在 `ps` 裡，等於把安全設定公開給同機所有程序看。
    public static let launcher = "/usr/bin/sandbox-exec"

    /// 要執行的命令，**結構化 argv**（I4：沒有整串命令字串這種東西）。
    public let argv: [String]
    public let profilePath: String
    public let timeout: Duration

    public init(argv: [String], profilePath: String, timeout: Duration) throws {
        guard let command = argv.first else { throw SandboxedCommandError.emptyArgv }
        guard command.hasPrefix("/") else {
            throw SandboxedCommandError.commandNotAbsolute(command)
        }
        guard profilePath.hasPrefix("/") else {
            throw SandboxedCommandError.profilePathNotAbsolute(profilePath)
        }
        self.argv = argv
        self.profilePath = profilePath
        self.timeout = timeout
    }

    /// 交給 `posix_spawn` 的完整 argv。
    ///
    /// **每個元素原樣傳遞、不經任何字串拼接**——這是 I4 在執行端的落地：
    /// 只要中間有一次 `joined(separator: " ")`，帶空白或 metacharacter 的參數
    /// 就會被重新切分，而那就是 shell injection。
    public var spawnArguments: [String] {
        [Self.launcher, "-f", profilePath] + argv
    }
}

/// 執行結束的分類。
///
/// 分這麼細是因為**它們要修的東西完全不同**：命令自己失敗（使用者的事）、
/// 沙箱擋住（profile 的事）、啟動失敗（白名單或路徑的事）、逾時（命令卡住）。
/// 全部歸成「失敗」的話，稽核紀錄就失去診斷價值。
public enum CommandDisposition: Sendable, Equatable {
    case succeeded
    /// 命令跑完但回非零。
    case failed(exitCode: Int32)
    /// `sandbox-exec` 沒能把命令跑起來。
    ///
    /// ⚠️ 判斷依據是 exit code 71，那是**真機觀察到的**（執行白名單外的程式時），
    /// 不是文件保證的。所以只當提示：它影響稽核裡的措辭，不影響任何安全判斷。
    case launchFailed(exitCode: Int32)
    case timedOut
    case killedBySignal(Int32)

    /// 真的有東西被執行成功嗎。稽核與 HUD 靠這個決定要不要說「已執行」。
    public var didExecute: Bool {
        switch self {
        case .succeeded, .failed: return true
        case .launchFailed, .timedOut, .killedBySignal: return false
        }
    }
}

public enum CommandOutcomeClassifier {
    /// `sandbox-exec` 無法執行目標程式時的 exit code（真機觀察，非文件保證）。
    static let launchFailureExitCode: Int32 = 71

    public static func classify(exitCode: Int32, signal: Int32? = nil, timedOut: Bool = false)
        -> CommandDisposition {
        // 逾時優先：逾時被殺的程序也會帶著訊號，先看逾時才不會把它誤報成「被訊號殺掉」。
        if timedOut { return .timedOut }
        if let signal { return .killedBySignal(signal) }
        if exitCode == 0 { return .succeeded }
        if exitCode == launchFailureExitCode { return .launchFailed(exitCode: exitCode) }
        return .failed(exitCode: exitCode)
    }
}

/// stdout / stderr 收進稽核前的截斷。
public enum OutputTruncator {
    public static let defaultLimit = 4_000

    /// 截斷時**留下明確標記**。沒有標記的話，被截掉的輸出看起來就像「命令只講了這麼多」——
    /// 而稽核紀錄一旦讓人誤以為看到了全部，它就從證據變成誤導。
    public static func truncate(_ output: String, limit: Int = defaultLimit) -> String {
        guard output.count > limit else { return output }
        let kept = String(output.prefix(limit))
        let dropped = output.count - limit
        return kept + "\n…（已截斷 \(dropped) 個字元）"
    }
}
