import CoreGraphics
// 設計：docs/design/v2_smart-capture-engine.md §B.4（焦點元件定義重點區域）
// 純邏輯（可單元測試）。真正的 AXUIElement 讀取在 SystemAXFocusProvider（🔒 真機）。

/// 焦點元件的精要資訊（由 AX 讀出，或測試餵入）。
public struct AXFocusedElement: Sendable, Equatable {
    public var role: String        // AXTextArea / AXTextField / AXButton…
    public var subrole: String?    // 如 AXSecureTextField（密碼欄）——用來確保永不記錄密碼
    public var frame: CGRect       // 螢幕座標
    public var value: String?      // AX value / 選取文字（可能為 nil）
    /// 所屬視窗標題（AXWindow 的 AXTitle）。**焦點識別用這個，不要用 value**——
    /// value 是欄位內容（終端機每輸出一字就變），拿來判斷「換視窗了嗎」會狂噴 FOCUS。
    public var windowTitle: String?
    /// 擁有這個焦點元件的程序（AXUIElementGetPid）。nil = 讀不到。
    ///
    /// 存在的理由是**對帳**：app 名稱來自 NSWorkspace，視窗標題來自 AX，兩條是獨立來源，
    /// 在切換的那一瞬間會不同步（AX 已經指到新 app，NSWorkspace 還說舊 app）。
    /// 有了擁有者才能發現「這兩個欄位不是在講同一個 app」，見
    /// `FocusChangeTracker.reconciledWindow`。
    public var ownerPID: Int32?
    public init(role: String, subrole: String? = nil, frame: CGRect,
                value: String? = nil, windowTitle: String? = nil,
                ownerPID: Int32? = nil) {
        self.role = role; self.subrole = subrole; self.frame = frame
        self.value = value; self.windowTitle = windowTitle
        self.ownerPID = ownerPID
    }
}

/// 由焦點元件算出的注意力重點區。
public struct FocusRegion: Sendable, Equatable {
    public var rect: CGRect
    public var role: String
    public var hasAXText: Bool     // 有 AX 文字 → 該區 tile 之後可略過 OCR（§B.4 accessibility-first）
    public init(rect: CGRect, role: String, hasAXText: Bool) {
        self.rect = rect; self.role = role; self.hasAXText = hasAXText
    }
}

/// 抽象焦點來源，讓區域計算可離線測試（真實作見 SystemAXFocusProvider）。
public protocol AXFocusProviding {
    /// 目前系統焦點元件；無焦點回 nil。
    func focusedElement() -> AXFocusedElement?
}

/// 把焦點元件映射成重點區，並決定打字時的注意力錨點（§B.3.1 / §B.4）。純值計算、可測。
public struct FocusRegionResolver: Sendable {
    /// 重點區最小尺寸（元件太小時向外擴到此，帶入周邊脈絡）。§B.3.1 焦點區約 600×400pt。
    public var minimumSize: CGSize
    public init(minimumSize: CGSize = CGSize(width: 600, height: 400)) {
        self.minimumSize = minimumSize
    }

    /// 置中於焦點元件、至少 minimumSize 的重點區；無焦點回 nil。
    public func region(for element: AXFocusedElement?) -> FocusRegion? {
        guard let e = element else { return nil }
        let w = max(e.frame.width, minimumSize.width)
        let h = max(e.frame.height, minimumSize.height)
        let rect = CGRect(x: e.frame.midX - w / 2, y: e.frame.midY - h / 2, width: w, height: h)
        let hasText = !(e.value?.isEmpty ?? true)
        return FocusRegion(rect: rect, role: e.role, hasAXText: hasText)
    }

    /// 便利：直接從 provider 讀焦點再算區域。
    public func region(from provider: AXFocusProviding) -> FocusRegion? {
        region(for: provider.focusedElement())
    }

    /// 打字時把注意力錨定在 focused element 中心（§B.4：打字常不在滑鼠處），否則用游標位置。
    public func attentionCenter(mouseLocation: CGPoint,
                                focusedElement: AXFocusedElement?,
                                isTyping: Bool) -> CGPoint {
        if isTyping, let e = focusedElement {
            return CGPoint(x: e.frame.midX, y: e.frame.midY)
        }
        return mouseLocation
    }
}
