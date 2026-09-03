import AppKit
import ApplicationServices
import CoPartnerCore
import ActionExecutor

// 主程序內的 UI 執行端（🔒 真機膠水，CI 只保證編譯）。step 53.6-B。
//
// ## 為什麼不在 XPC service 裡
//
// 點按 / 輸入 / 捲動需要使用者 session 的權限（輔助使用），而且**天生就在使用者
// 權限內執行**——沒有沙箱可以圍它（威脅模型 R2）。放進 service 只會製造一個
// 「看起來被隔離了」的假象：service 與主 app 同 uid（R5 實測），沙箱 profile 也
// 擋不住 CGEvent。所以誠實一點，就放在主程序，並且把防線寫清楚：
// **本地風險分級 → HUD 人工確認 → 座標驗證 → 這裡。**
//
// ## 這一層最容易出的錯不是「失敗」，是「成功地做錯事」
//
// 兩個具體形狀，兩個都不會報錯：
//
// 1. **沒有輔助使用權限時 `CGEvent.post` 靜默什麼都不做。** 由 `UIActionGate` 擋，
//    在送出之前就拒絕。
// 2. **座標算錯就點到別的地方。** 由 `ScreenCoordinateMapper` 擋，越界一律拒絕不夾邊。
//
// 所以這個檔案裡幾乎沒有判斷邏輯——判斷全在 CoPartnerKit 那兩個純值型別裡，
// 這裡只負責把已經驗過的東西送出去。
@MainActor
final class UIActionPerformer {

    /// 這個執行端**有沒有真的送事件出去**。
    ///
    /// 與 `ExecutorService.willExecuteActions` 同一種寫法：一個事實的陳述，不是開關。
    /// `UIActionGate.decide` 拿它去判定，所以翻成 true 的那一刻，閘門會自動開始放行，
    /// 不需要有人記得回來改別的地方。
    ///
    /// **翻開前的驗收**：用選單的「UI 乾跑」確認座標換算與命中的元件都正確
    /// ——那顆按鈕不會送出任何事件（見 `dryRun`）。翻開是 step 53.6-C。
    static let willPerformUIActions = false

    /// 事件來源。用 `.combinedSessionState`：`.hidSystemState` 會忽略其他程序注入的
    /// 修飾鍵狀態，導致組合鍵在某些情境下只按到主鍵。
    private func makeSource() -> CGEventSource? {
        CGEventSource(stateID: .combinedSessionState)
    }

    // MARK: - 真執行

    func perform(_ action: ProposedAction) throws {
        let trusted = AXIsProcessTrusted()
        switch UIActionGate.decide(kind: action.kind, accessibilityTrusted: trusted,
                                   canPerform: Self.willPerformUIActions) {
        case .refuse(let reason): throw ExecutionError.uiActionRefused(reason)
        case .perform: break
        }
        guard let source = makeSource() else {
            throw ExecutionError.uiActionRefused("建立不了 CGEventSource")
        }
        switch action.kind {
        case let .click(x, y):      try click(x: x, y: y, source: source)
        case let .typeText(text):   try type(text, source: source)
        case let .keypress(raw):    try press(raw, source: source)
        case let .scroll(dx, dy):   try scroll(dx: dx, dy: dy, source: source)
        // 刻意窮舉、不用 default：日後 Kind 加了新的 UI 動作，這裡會編譯失敗而不是
        // 靜默地什麼都不做——後者會表現成「按了執行但沒反應」，最難查的那種。
        case .screenshot, .shell, .readFile, .writeFile, .outboundComms:
            throw ExecutionError.uiActionRefused("UI 執行端不處理 \(action.kind.summary)")
        }
    }

    private func click(x: Int, y: Int, source: CGEventSource) throws {
        let point = try globalPoint(x: x, y: y)
        guard let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                                 mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                               mouseCursorPosition: point, mouseButton: .left) else {
            throw ExecutionError.uiActionRefused("建立不了滑鼠事件")
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    /// 文字輸入走 `keyboardSetUnicodeString`，**不走鍵碼**：鍵碼是 ANSI 佈局的**位置**，
    /// 用它打字在非美式佈局上會打出別的字。Unicode 字串與佈局無關。
    ///
    /// 分段送：單一事件塞太長的字串在實務上會被截斷，而截斷後的文字**看起來仍然正常**
    /// ——只是少了後半段，是那種要盯著才看得出來的錯。
    private func type(_ text: String, source: CGEventSource) throws {
        for chunk in Self.chunked(text, size: 16) {
            var utf16 = Array(chunk.utf16)
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                throw ExecutionError.uiActionRefused("建立不了鍵盤事件")
            }
            down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }

    private func press(_ raw: String, source: CGEventSource) throws {
        let chord: KeyChord
        do { chord = try KeyChord.parse(raw) } catch {
            throw ExecutionError.uiActionRefused("組合鍵解析不了「\(raw)」：\(error)")
        }
        guard let code = VirtualKeyMap.keyCode(for: chord.key) else {
            throw ExecutionError.uiActionRefused("按不出這個鍵：\(chord.canonical)")
        }
        guard let down = CGEvent(keyboardEventSource: source,
                                 virtualKey: CGKeyCode(code), keyDown: true),
              let up = CGEvent(keyboardEventSource: source,
                               virtualKey: CGKeyCode(code), keyDown: false) else {
            throw ExecutionError.uiActionRefused("建立不了鍵盤事件")
        }
        let flags = Self.eventFlags(for: chord.modifiers)
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func scroll(dx: Int, dy: Int, source: CGEventSource) throws {
        guard ScreenCoordinateMapper.isReasonableScroll(dx: dx, dy: dy) else {
            throw ExecutionError.uiActionRefused(
                "捲動量超出上限（\(dx),\(dy)）——多半是單位搞錯了，該停下來問人")
        }
        guard let event = CGEvent(scrollWheelEvent2Source: source, units: .line,
                                  wheelCount: 2, wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0) else {
            throw ExecutionError.uiActionRefused("建立不了捲動事件")
        }
        event.post(tap: .cghidEventTap)
    }

    // MARK: - 乾跑（不送任何事件）

    /// 一句話判定，給選單用。完整報告在檔案裡（見 `AppCoordinator.runUIDryRun`）。
    ///
    /// 存在的理由很具體：真機第一次跑 UI 乾跑時，選單把報告截在第 10 行，
    /// **而被截掉的正好是 `⌘Q` 的鍵碼與後果那兩行**——也就是最該看的那一段。
    /// 這個專案在「報告塞進選單被截斷」上已經栽過三次，shell 乾跑早就改成寫檔案。
    func verdict(_ action: ProposedAction) -> String {
        let trusted = AXIsProcessTrusted()
        guard trusted else { return "UI 乾跑：❌ 未授權輔助使用（CGEvent 會靜默失敗）" }
        guard let geometry = ScreenGeometryProvider.mainDisplay() else {
            return "UI 乾跑：❌ 讀不到顯示器幾何"
        }
        var line = String(format: "UI 乾跑：權限已授權・顯示器 %.0f×%.0f px",
                          geometry.imagePixelSize.width, geometry.imagePixelSize.height)
        if NSScreen.screens.count > 1 { line += "・⚠️ \(NSScreen.screens.count) 台螢幕" }
        if case let .click(x, y) = action.kind,
           let point = try? ScreenCoordinateMapper.globalPoint(
            fromModelPoint: CGPoint(x: x, y: y), in: geometry) {
            line += String(format: "・中央 (%d,%d)→(%.0f,%.0f) 命中 %@",
                           x, y, point.x, point.y, Self.describeElement(at: point))
        }
        return line
    }

    /// 「如果執行，游標會落在哪裡、那裡有什麼」。**這個方法裡沒有任何 `post` 呼叫。**
    ///
    /// 報告命中的 AX 元件是重點：座標算錯不會報錯，只會點到別的地方，而
    /// 「AXButton『刪除』」與「AXButton『儲存』」這兩行字是唯一能在事前看出差別的東西。
    func dryRun(_ action: ProposedAction) -> String {
        let trusted = AXIsProcessTrusted()
        var lines = ["UI 乾跑：\(action.kind.summary)",
                     "輔助使用權限：\(trusted ? "已授權" : "❌ 未授權（CGEvent 會靜默失敗）")"]

        // 多螢幕是這一層的**已知風險**，而且它不會報錯：宣告給模型的尺寸取自
        // 「目前有鍵盤焦點的那一台」，而焦點在宣告與執行之間可能已經換過。
        // 換了之後每一次點擊都會落在錯的螢幕上，畫面上看起來只是「點錯地方」。
        let screenCount = NSScreen.screens.count
        if screenCount > 1 {
            lines.append("⚠️ 接了 \(screenCount) 台螢幕——宣告尺寸取自目前有焦點的那一台，"
                         + "焦點若在宣告與執行之間改變，座標的意義會跟著變")
        }

        switch UIActionGate.decide(kind: action.kind, accessibilityTrusted: trusted,
                                   canPerform: UIActionPerformer.willPerformUIActions) {
        case .perform:          lines.append("閘門：放行")
        case .refuse(let why):  lines.append("閘門：拒絕（\(why)）")
        }

        guard let geometry = ScreenGeometryProvider.mainDisplay() else {
            lines.append("顯示器：讀不到")
            return lines.joined(separator: "\n")
        }
        lines.append(String(format: "顯示器：宣告給模型 %.0f×%.0f px・實際 %.0f×%.0f pt・原點 (%.0f,%.0f)",
                            geometry.imagePixelSize.width, geometry.imagePixelSize.height,
                            geometry.display.sizePoints.width, geometry.display.sizePoints.height,
                            geometry.display.globalOriginPoints.x, geometry.display.globalOriginPoints.y))

        if case let .click(x, y) = action.kind {
            do {
                let point = try globalPoint(x: x, y: y)
                lines.append(String(format: "模型座標 (%d,%d) → 全域 (%.1f,%.1f)", x, y, point.x, point.y))
                lines.append("那個位置上是：\(Self.describeElement(at: point))")
            } catch {
                lines.append("座標換算被拒：\(error)")
            }
        }
        if case let .keypress(raw) = action.kind {
            if let chord = try? KeyChord.parse(raw) {
                let code = VirtualKeyMap.keyCode(for: chord.key).map(String.init) ?? "❌ 按不出來"
                lines.append("組合鍵 \(raw) → \(chord.canonical)・鍵碼 \(code)")
                if let consequence = DestructiveKeyChords.consequence(of: chord) {
                    lines.append("⚠️ 後果：\(consequence)")
                }
            } else {
                lines.append("組合鍵 \(raw) → ❌ 解析不了")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - 共用

    private func globalPoint(x: Int, y: Int) throws -> CGPoint {
        guard let geometry = ScreenGeometryProvider.mainDisplay() else {
            throw ExecutionError.uiActionRefused("讀不到顯示器幾何")
        }
        do {
            return try ScreenCoordinateMapper.globalPoint(
                fromModelPoint: CGPoint(x: x, y: y), in: geometry)
        } catch {
            throw ExecutionError.uiActionRefused("座標無效：\(error)")
        }
    }

    static func eventFlags(for modifiers: Set<KeyChord.Modifier>) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.function) { flags.insert(.maskSecondaryFn) }
        return flags
    }

    static func chunked(_ text: String, size: Int) -> [String] {
        guard size > 0, !text.isEmpty else { return text.isEmpty ? [] : [text] }
        var result: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if current.count >= size { result.append(current); current = "" }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// 全域座標上那一點是什麼元件。讀不到就說讀不到——**不可以回空字串**，
    /// 那會讓「那裡沒有東西」與「我們讀不到」在報告上長得一樣。
    private static func describeElement(at point: CGPoint) -> String {
        var element: AXUIElement?
        let status = AXUIElementCopyElementAtPosition(
            AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &element)
        guard status == .success, let element else {
            return "（讀不到，AXError \(status.rawValue)——多半是沒有輔助使用權限）"
        }
        func attribute(_ name: String) -> String? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success
            else { return nil }
            return value as? String
        }
        let role = attribute(kAXRoleAttribute) ?? "未知角色"
        let label = attribute(kAXTitleAttribute)
            ?? attribute(kAXDescriptionAttribute)
            ?? attribute(kAXValueAttribute)
        guard let label, !label.isEmpty else { return role }
        return "\(role)「\(label.prefix(60))」"
    }
}
