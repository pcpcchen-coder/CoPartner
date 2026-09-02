import XCTest
import CoPartnerCore

/// 記憶體取樣的檔案格式。
///
/// 這個檔案是**事後分析的唯一資料來源**——先前每一輪診斷都靠人截圖選單、再把數字念出來，
/// 又慢又有損。所以格式要守兩件事：欄位不會錯位，以及**取樣來源分得出來**
/// （「停止後幾秒取的」與「等它落定才取的」是完全不同的數字，先前每一輪都栽在這裡）。
final class MemoryLogFormatTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_756_800_000)

    func testLineHasExactlyFiveTabSeparatedFields() {
        let line = MemoryLogFormat.line(at: t0, footprintMB: 130.4,
                                        regime: "觀察中", steps: 41, source: .tick)
        let fields = line.components(separatedBy: MemoryLogFormat.separator)
        XCTAssertEqual(fields.count, 5, line)
        XCTAssertEqual(fields[1], "130.4")
        XCTAssertEqual(fields[2], "觀察中")
        XCTAssertEqual(fields[3], "41")
        XCTAssertEqual(fields[4], "tick")
    }

    /// **欄位裡不可以出現分隔符**，否則整個檔案的欄位會錯位而且看起來完全正常。
    /// 狀態與來源都是固定字串，這條測試是釘住「以後別把自由文字塞進來」。
    func testNoFieldCanContainTheSeparator() {
        for source in MemoryLogFormat.Source.allCases {
            XCTAssertFalse(source.rawValue.contains(MemoryLogFormat.separator), source.rawValue)
        }
        for regime in ["閒置", "觀察中", "接手中"] {
            let line = MemoryLogFormat.line(at: t0, footprintMB: 1, regime: regime,
                                            steps: 0, source: .menu)
            XCTAssertEqual(line.components(separatedBy: MemoryLogFormat.separator).count, 5)
        }
    }

    /// 空狀態要有替代值，不能留空欄位——空欄位在 TSV 裡看不出來是「沒有」還是「錯位」。
    func testEmptyRegimeBecomesPlaceholder() {
        let fields = MemoryLogFormat.line(at: t0, footprintMB: 1, regime: "",
                                          steps: 0, source: .menu)
            .components(separatedBy: MemoryLogFormat.separator)
        XCTAssertEqual(fields[2], "?")
    }

    /// 時間可排序（ISO-8601），而且同一時刻永遠印成同一個字串。
    func testTimestampIsStableAndSortable() {
        let a = MemoryLogFormat.timestamp(t0)
        let b = MemoryLogFormat.timestamp(t0)
        XCTAssertEqual(a, b)
        XCTAssertLessThan(a, MemoryLogFormat.timestamp(t0.addingTimeInterval(86_400)))
    }

    // MARK: - 裁切

    private func log(lines: Int) -> String {
        var text = MemoryLogFormat.header + "\n"
        for i in 0..<lines {
            text += MemoryLogFormat.line(at: t0.addingTimeInterval(Double(i)),
                                         footprintMB: Double(i), regime: "閒置",
                                         steps: i, source: .tick) + "\n"
        }
        return text
    }

    /// 沒超過上限就原封不動——裁切要是每次都重寫檔案，這個工具自己就會拖慢程式。
    func testUnderLimitIsUntouched() {
        let text = log(lines: 10)
        XCTAssertEqual(MemoryLogFormat.trimmed(text, maxLines: 100), text)
    }

    /// 保留**最新**的，並把 header 補回最前面。
    /// 診斷看的永遠是最近發生的事；而丟掉 header 會讓檔案失去版本標記。
    func testTrimKeepsNewestAndRestoresHeader() {
        let trimmed = MemoryLogFormat.trimmed(log(lines: 100), maxLines: 10)
        XCTAssertTrue(trimmed.hasPrefix("# CoPartner 記憶體取樣 v1"), trimmed.prefix(60).description)
        let body = trimmed.split(separator: "\n").filter { !$0.hasPrefix("#") }
        XCTAssertEqual(body.count, 10)
        // 最後一行應該是第 99 筆（足跡 99.0），不是第 9 筆。
        XCTAssertTrue(body.last!.contains("99.0"), String(body.last!))
        XCTAssertTrue(body.first!.contains("90.0"), String(body.first!))
    }

    /// 一個為了診斷記憶體而無上限成長的日誌會很難堪。上限要真的生效。
    func testTrimIsIdempotent() {
        let once = MemoryLogFormat.trimmed(log(lines: 100), maxLines: 10)
        XCTAssertEqual(MemoryLogFormat.trimmed(once, maxLines: 10), once)
    }
}
