import XCTest
import ScriptNarrator

/// step 54 dogfood 真機回歸：step 的 app 標錯。
///
/// 真機症狀：L1 區整串 step 都掛著 `CoPartner`，內容講的卻是 AnyDesk 和系統設定。
/// 成因是 `inferApp` 取「第一行的 app」，而視窗是舊到新排的——第一行是這段時間的
/// **最舊**事件，於是每個 step 標的是「這段開始時你在哪」而不是「這段主要在哪」。
///
/// 這不只是顯示難看：`MemoryStore` 依 app 存放 step，標錯等於之後全部查錯戶。
final class InferAppAttributionTests: XCTestCase {

    /// 核心回歸：視窗開頭殘留的舊 app 不該蓋過整段的主體。
    func testDominantAppWinsOverFirstLine() {
        let lines = [
            #"[21:33:41.079] SWITCH  app=CoPartner win="""#,        // 最舊：只有這一行
            #"[21:33:43.267] SWITCH  app=系統設定 win="""#,
            #"[21:33:50.048] SCROLL  app=系統設定 dir=up dist=3"#,
            #"[21:33:50.561] SCROLL  app=系統設定 dir=down dist=30"#,
        ]
        XCTAssertEqual(RuleBasedNarrator.inferApp(lines), "系統設定")
    }

    /// 平手時取**較晚**出現的：一個 step 通常結束在使用者當下所在的 app，
    /// 那也是接手時最可能相關的那個。
    func testTieBreaksToTheMoreRecentApp() {
        let lines = [
            "SWITCH  app=Claude win=\"\"",
            "SWITCH  app=AnyDesk win=\"新增連線\"",
        ]
        XCTAssertEqual(RuleBasedNarrator.inferApp(lines), "AnyDesk")
    }

    func testReturnsNilWhenNoAppField() {
        XCTAssertNil(RuleBasedNarrator.inferApp([
            #"[12:00:00.000] TYPE    field=AXTextArea text="abc""#,
            #"[12:00:01.000] PASTE   chars=12 preview="…""#,
        ]))
        XCTAssertNil(RuleBasedNarrator.inferApp([]))
    }

    // MARK: - 單行解析

    /// app 名稱本身可以有空白。切在第一個空白會把 Chrome 切成 "Google"——
    /// 那會讓同一個 app 被算成兩個，佔比統計跟著失準。
    func testAppNameWithSpacesIsNotTruncated() {
        XCTAssertEqual(RuleBasedNarrator.appName(in: #"SWITCH  app=Google Chrome win="分頁""#),
                       "Google Chrome")
        XCTAssertEqual(RuleBasedNarrator.appName(in: #"FOCUS   app=Visual Studio Code win="a.swift""#),
                       "Visual Studio Code")
    }

    /// 各種事件格式的欄位鍵都要能當切點（win= / dir= / dist=）。
    func testStopsAtAnyFieldKey() {
        XCTAssertEqual(RuleBasedNarrator.appName(in: #"SCROLL  app=Claude dir=up dist=43"#), "Claude")
        XCTAssertEqual(RuleBasedNarrator.appName(in: #"SWITCH  app=系統設定 win="""#), "系統設定")
    }

    func testHandlesMissingOrEmptyAppField() {
        XCTAssertNil(RuleBasedNarrator.appName(in: "WATCH   video"))
        XCTAssertNil(RuleBasedNarrator.appName(in: "SWITCH  app="))
        XCTAssertEqual(RuleBasedNarrator.appName(in: "SWITCH  app=Claude"), "Claude",
                       "沒有後續欄位時取到行尾")
    }

    // MARK: - 接到敘事器上

    /// 規則式敘事器產出的 step 也要標對 app（它是模型不可用時的降級路徑）。
    func testRuleBasedNarratorLabelsDominantApp() async {
        let lines = [
            #"[21:33:41.079] SWITCH  app=CoPartner win="""#,
            #"[21:34:34.093] SWITCH  app=AnyDesk win="新增連線""#,
            #"[21:34:45.275] SCROLL  app=AnyDesk dir=down dist=19"#,
        ]
        let step = await RuleBasedNarrator().narrate(lines)
        XCTAssertEqual(step?.app, "AnyDesk")
    }
}
