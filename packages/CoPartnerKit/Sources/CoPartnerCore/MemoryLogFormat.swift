import Foundation
// 記憶體取樣的檔案格式（step 53.7）。
//
// 為什麼要落檔：先前每一輪診斷都靠人截圖選單、再由人把數字念出來。那條路徑
// 又慢又有損——「0 分跨度」那個關鍵瑕疵就是因為截圖只看得到當下那一行，
// 看不到它是什麼時候取的。落成檔案之後，整條曲線都在，事後想怎麼算都行。
//
// 格式選 TSV 而不是 JSON：**人要看得懂，機器也要好剖**。JSON 一行一個物件的話，
// 使用者打開檔案看到的是一堆括號；CSV 又會被中文欄位裡的逗號咬到。
// TSV 兩邊都成立，而且欄位裡不可能出現 tab（狀態與來源都是固定字串）。
//
// 檔案有行數上限。一個為了診斷記憶體而無上限成長的日誌會很難堪——
// 這已經是第二次要寫這句話了（第一次是 `MemorySampleLog` 的環狀緩衝）。
public enum MemoryLogFormat {

    /// 欄位分隔符。刻意獨立成常數：格式改一次就要改三個地方的話，遲早會不一致。
    public static let separator = "\t"

    /// 版本號在第一行。日後改欄位時，舊檔案還讀得出來是哪個版本寫的。
    ///
    /// **v2（2026-09-02）**：加上「模型」欄。第一份真實日誌分析到一半才發現，
    /// 沒有任何欄位記錄當下 Apple Intelligence 是開還是關——而整個診斷的關鍵對照
    /// 就是那個開關。日誌若不能自己說明它是在什麼條件下錄的，事後就只能靠記憶補，
    /// 而記憶正是這一整串診斷裡最不可靠的環節。
    public static let header = """
        # CoPartner 記憶體取樣 v2
        # 時間\(separator)足跡MB\(separator)狀態\(separator)記憶step數\(separator)來源\(separator)模型
        """

    /// 取樣的來源。**這一欄是重點**：它讓「停止後幾秒取的」與「等它落定後取的」
    /// 分得開，而先前每一輪診斷都栽在分不開這件事上。
    public enum Source: String, Sendable, CaseIterable {
        case menu       = "menu"        // 使用者打開選單
        case transition = "transition"  // 開始／停止觀察的前後
        case tick       = "tick"        // 觀察中的定期取樣（搭既有的敘事迴圈，不另外喚醒）
        case settle     = "settle"      // 停止觀察後隔一段時間的落定值
    }

    /// 本地模型當下可不可用。**日誌要能自己說明它是在什麼條件下錄的**——
    /// 見 `header` 的 v2 註解。
    public enum ModelState: String, Sendable, CaseIterable {
        case available   = "可用"
        case unavailable = "不可用"

        public init(available: Bool) { self = available ? .available : .unavailable }
    }

    /// 一行取樣。時間用 ISO-8601（含時區）——本機時間看得懂，事後也排得出序。
    public static func line(at: Date, footprintMB: Double, regime: String,
                            steps: Int, source: Source, model: ModelState) -> String {
        [Self.timestamp(at),
         String(format: "%.1f", footprintMB),
         regime.isEmpty ? "?" : regime,
         String(steps),
         source.rawValue,
         model.rawValue].joined(separator: separator)
    }

    /// 把日誌裁到 `maxLines` 行以內，**保留最新的**並把 header 補回最前面。
    ///
    /// 保留最新而不是最舊：診斷看的永遠是最近發生的事。
    public static func trimmed(_ contents: String, maxLines: Int) -> String {
        let limit = max(1, maxLines)
        let body = contents
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix("#") && !$0.isEmpty }
        guard body.count > limit else { return contents }
        return header + "\n" + body.suffix(limit).joined(separator: "\n") + "\n"
    }

    /// 每次都新建一個 formatter，不共用一份。
    ///
    /// 兩個理由。其一是 Swift 6 嚴格並行：`ISO8601DateFormatter` 不是 `Sendable`，
    /// 放成 `static let` 直接編不過（這一行原本就是這樣掛掉的）。其二更根本——
    /// 共用一份可變的 formatter 本來就是經典的資料競爭來源，而繞過檢查
    /// （`nonisolated(unsafe)`）換到的只是「省下一次建構」。
    /// 這個函式最頻繁也就每 15 秒被呼叫一次，那點成本量不出來。
    public static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .current
        return formatter.string(from: date)
    }
}
