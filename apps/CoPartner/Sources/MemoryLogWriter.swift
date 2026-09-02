import Foundation
import CoPartnerCore
// 🔒 真機膠水：把記憶體取樣一行一行寫進檔案。CI 只保證編譯（格式與裁切在 CoPartnerCore）。
//
// 用 `FileHandle.seekToEnd` 附加而不是「讀整個檔 → 加一行 → 寫回」：
// 後者在檔案長到幾千行之後，每一次取樣都要搬一次整個檔案——一個為了診斷效能問題
// 而拖慢程式的工具。
final class MemoryLogWriter {

    /// 行數上限。超過就裁掉最舊的一半——一次裁一半而不是一次裁一行，
    /// 否則到達上限之後每一次寫入都要重寫整個檔案。
    private static let maxLines = 20_000

    private let url: URL
    private var writesSinceTrimCheck = 0

    var path: String { url.path }

    init(directory: String) {
        self.url = URL(fileURLWithPath: directory).appendingPathComponent("memory-log.tsv")
        try? FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? (MemoryLogFormat.header + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func append(at: Date, footprintMB: Double, regime: String, steps: Int,
                source: MemoryLogFormat.Source, model: MemoryLogFormat.ModelState) {
        let line = MemoryLogFormat.line(at: at, footprintMB: footprintMB, regime: regime,
                                        steps: steps, source: source, model: model) + "\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            // 檔案不見了（使用者刪掉、或第一次寫失敗）→ 重建，不要靜默丟掉取樣。
            try? (MemoryLogFormat.header + "\n" + line).write(to: url, atomically: true,
                                                              encoding: .utf8)
        }
        // 每 500 行才檢查一次長度：檢查本身要讀整個檔案，每次都做就是自找麻煩。
        writesSinceTrimCheck += 1
        if writesSinceTrimCheck >= 500 {
            writesSinceTrimCheck = 0
            trimIfNeeded()
        }
    }

    private func trimIfNeeded() {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return }
        let lineCount = contents.reduce(0) { $1 == "\n" ? $0 + 1 : $0 }
        guard lineCount > Self.maxLines else { return }
        try? MemoryLogFormat.trimmed(contents, maxLines: Self.maxLines / 2)
            .write(to: url, atomically: true, encoding: .utf8)
    }
}
