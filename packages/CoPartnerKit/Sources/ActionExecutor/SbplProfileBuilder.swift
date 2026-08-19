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
    public init() {}

    /// 產生 profile。任何一個路徑不安全就整個失敗——**不做「跳過壞的那條」**：
    /// 少一條 deny 規則的 profile 看起來仍然正常，但防線已經有洞。
    public func profile(execAllowlist: [String],
                        workspace: String,
                        deniedSubpaths: [String]) throws -> String {
        let workspacePath = try Self.sanitize(workspace)
        let execPaths = try execAllowlist.map(Self.sanitize)
        let deniedPaths = try deniedSubpaths.map(Self.sanitize)

        var lines = [
            "(version 1)",
            "(deny default)",           // deny-default：一切先拒再逐項開
            "(deny network*)",          // 沙箱內一律斷網（T5 外洩）
        ]
        if !execPaths.isEmpty {
            let literals = execPaths.map { "(literal \(Self.quoted($0)))" }.joined(separator: " ")
            lines.append("(allow process-exec \(literals))")
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
