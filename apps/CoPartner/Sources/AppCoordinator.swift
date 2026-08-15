import SwiftUI
import Combine
import AppKit
import KeyboardShortcuts
import CoreVideo
import CoreMedia
import ImageIO
@preconcurrency import ScreenCaptureKit
import CoPartnerCore
import CaptureEngine
import ScriptNarrator
import CloudRouter
import ActionExecutor
// 串接各子系統的協調者（🔒 真機膠水：實際觀察 / 熱鍵行為於 step 10 dogfood 驗收）。
// 可測邏輯放在 CoPartnerKit（CaptureSessionState / EventLogFeed / FocusChangeTracker）。

extension KeyboardShortcuts.Name {
    static let toggleObserve = Self("toggleObserve", default: .init(.o, modifiers: [.control, .option, .command]))
    static let emergencyStop = Self("emergencyStop", default: .init(.period, modifiers: [.control, .option, .command]))
    static let triggerIntervention = Self("triggerIntervention", default: .init(.space, modifiers: [.control, .option, .command]))
}

/// EgressGate 的 scrubber：接 step 7 的 PIIMasker（出境前遮罩，威脅 T6）。
struct PIIMaskerScrubber: PIIScrubbing {
    func scrub(_ text: String) -> (clean: String, foundPII: Bool) {
        let clean = PIIMasker.redact(text)
        return (clean, clean != text)
    }
}

@MainActor
final class AppCoordinator: ObservableObject {
    @Published private var session = CaptureSessionState()
    @Published var lastStepSummary: String = "尚未開始觀察"
    @Published private(set) var recentLines: [String] = []
    @Published private(set) var captureSummary: String = "螢幕擷取：待真機啟用（step 18）"
    @Published private(set) var screenTextSummary: String = "畫面文字：未啟用"

    var isIdle: Bool { session.mode == .idle }
    var statusIcon: String {
        switch session.mode {
        case .idle: return "eye.slash"
        case .observing: return "eye"
        case .intervening: return "wand.and.stars"
        }
    }

    private var feed = EventLogFeed(capacity: 300)
    private var focusTracker = FocusChangeTracker()
    private let axProvider = SystemAXFocusProvider()
    private var inputTap: InputEventTap?
    private var workspaceObserver: NSObjectProtocol?
    private var streamTask: Task<Void, Never>?
    private var captureActivity = CaptureActivity()
    private var captureTask: Task<Void, Never>?
    private var captureProducer: SCKFrameProducer?
    private var captureEngine: CaptureEngine?
    private var captureStartTask: Task<Void, Never>?

    // 局部 OCR（step 29）：截焦點畫面 → sidecar /ocr → 摘要。黑名單/自身 app 從 source 排除（§G）。
    private let ocrRecognizer = SidecarOCRRecognizer()
    private var ocrTask: Task<Void, Never>?
    private lazy var ocrBlacklist = CaptureBlacklist(ownBundleID: Bundle.main.bundleIdentifier ?? "com.copartner.app")

    // 接手鏈（step 49）：世代時鐘為 token 作廢的單一權威（威脅 I7）。
    @Published private(set) var takeoverSummary: String = "接手：未啟動"
    private let handoffGeneration = HandoffGeneration()
    private var takeoverModel: TakeoverSessionModel?
    private var handoffTask: Task<Void, Never>?
    private let cloudRouter = CloudRouter()   // 無 transport：真雲端傳輸 🔒 step 53

    init() { registerHotkeys() }

    /// ⌃⌥⌘O 切換觀察、⌃⌥⌘. 緊急停止（全域熱鍵；實際觸發需真機驗收）。
    private func registerHotkeys() {
        KeyboardShortcuts.onKeyUp(for: .toggleObserve) { [weak self] in
            MainActor.assumeIsolated { self?.toggleObserving() }
        }
        KeyboardShortcuts.onKeyUp(for: .emergencyStop) { [weak self] in
            MainActor.assumeIsolated { self?.stopAll() }
        }
        KeyboardShortcuts.onKeyUp(for: .triggerIntervention) { [weak self] in
            MainActor.assumeIsolated { self?.triggerIntervention() }
        }
    }

    func toggleObserving() {
        if session.mode == .idle {
            session.toggleObserve()   // → observing
            startPipeline()
        } else {
            stopAll()
        }
    }

    /// 緊急停止：任何狀態 → idle，拆掉所有觀察來源 + 中止接手全鏈（威脅 I7）。冪等。
    func stopAll() {
        abortHandoff(reason: "已中止（緊急停止）")
        guard session.mode != .idle else { return }
        session.stopAll()
        teardownPipeline()
        lastStepSummary = "已停止觀察"
    }

    /// ⌃⌥⌘Space / 選單「立即介入」（step 49）：
    /// 打包 ContextEnvelope（劇本主體）→ EgressGate（PII 遮罩 + PIPL 硬牆）→ CloudRouter.handoff。
    /// PIPL 命中 → 整包不出境、僅本地。真雲端傳輸未接（🔒 step 53）→ 走完整條鏈後以「尚未接線」收尾。
    func triggerIntervention() {
        guard session.mode == .observing else {          // 觀察中才可接手
            takeoverSummary = (session.mode == .intervening) ? "接手：進行中" : "接手：需先開始觀察"
            return
        }
        let lines = recentLines
        let envelope = EnvelopeBuilder().build(
            now: Date(),
            steps: [],                                   // 真 L1 取材待 Narrator 接入 app 管線（Phase E 接線）
            sessionSummary: lines.suffix(10).joined(separator: "\n"),
            openLoop: lines.last ?? "（無最近操作）",
            clipboard: NSPasteboard.general.string(forType: .string))
        let gate = EgressGate(
            scrubber: PIIMaskerScrubber(),
            piplDetector: { PIIMasker.detect($0).contains(.chinaID) })   // PIPL 硬牆：中國個資永不出境
        switch gate.check(envelope) {
        case .blocked(let reason):
            takeoverSummary = "接手：PIPL 封鎖（\(reason)）— 僅本地處理，不出境"
        case .allow(let cleanEnvelope):
            session.beginIntervention()
            var model = TakeoverSessionModel(policy: cleanEnvelope.takeover.policy,
                                             generationClock: handoffGeneration)
            model.begin()
            takeoverModel = model
            takeoverSummary = "接手：交棒中…"
            let router = cloudRouter
            handoffTask = Task { [weak self] in
                do {
                    let stream = await router.handoff(cleanEnvelope,
                                                      systemPrompt: "CoPartner takeover",
                                                      referencePrefix: "")
                    for try await proposal in stream {
                        guard let self else { return }
                        self.takeoverSummary = "接手提議：\(proposal.kind.summary)"
                    }
                    guard let self else { return }
                    self.takeoverModel?.complete()
                    self.takeoverSummary = "接手：完成"
                    self.session.endIntervention()
                } catch {
                    guard let self else { return }
                    let message = (error as? HandoffError == .noTransport)
                        ? "雲端傳輸尚未接線（step 53）" : error.localizedDescription
                    self.takeoverSummary = "接手：\(message)"
                    self.takeoverModel = nil
                    self.session.endIntervention()       // 失敗 → 回觀察，事件日誌不中斷
                }
            }
        }
    }

    /// 中止接手鏈：取消串流、作廢世代 token（I7）、回觀察/停止。冪等。
    private func abortHandoff(reason: String) {
        handoffTask?.cancel()
        handoffTask = nil
        if takeoverModel != nil {
            takeoverModel?.stop()                        // 內含 generation.abort()
            takeoverModel = nil
            takeoverSummary = "接手：\(reason)"
        }
        handoffGeneration.abort()                        // 冪等保險：任何在途 token 一律作廢
    }

    // MARK: - Pipeline（🔒 真機膠水）

    private func startPipeline() {
        feed = EventLogFeed(capacity: 300)   // 每次觀察用全新 feed
        focusTracker = FocusChangeTracker()  // 重置焦點基準
        lastStepSummary = "觀察中…"

        let currentFeed = feed
        streamTask = Task { [weak self] in
            for await lines in currentFeed.updates {
                guard let self else { return }
                self.recentLines = lines
                if let last = lines.last { self.lastStepSummary = last }
            }
        }

        // NSWorkspace 應用切換：免權限、最可靠的骨架訊號。
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let name = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.localizedName ?? "?"
            Task { @MainActor in self?.pollFocus(app: name) }
        }

        // 輸入事件 tap：需 Input Monitoring；失敗（缺權限）則僅靠 NSWorkspace。
        let tap = InputEventTap { [weak self] captured in
            Task { @MainActor in self?.handleInput(captured) }
        }
        _ = tap.start()
        inputTap = tap

        startCapture()   // 螢幕擷取（需 Screen Recording；失敗則不影響事件日誌）
        startOCRLoop()   // 局部 OCR（需 sidecar 起著；失敗則不影響事件日誌與擷取）
    }

    /// 節流 OCR 迴圈：每 ~3s 截一次焦點顯示器 → 存暫存 PNG → sidecar /ocr → 摘要。
    /// 全程 guarded：sidecar 沒起 / 截圖失敗 → 摘要顯示未啟用，其餘子系統照常。
    private func startOCRLoop() {
        screenTextSummary = "畫面文字：啟動中…"
        ocrTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.session.mode != .idle else { return }
                await self.ocrTick()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func ocrTick() async {
        do {
            let content = try await SCShareableContent.current
            guard session.mode != .idle, !Task.isCancelled else { return }
            guard let display = content.displays.first else {
                screenTextSummary = "畫面文字：找不到顯示器"; return
            }
            // 黑名單 + 自身 app 從截圖源頭排除（隱私 §G / step 56）。
            let excluded = content.applications.filter {
                ocrBlacklist.isBlocked(bundleID: $0.bundleIdentifier, appName: $0.applicationName)
            }
            let filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("copartner-ocr.png")
            try Self.savePNG(image, to: url)
            let segments = try await ocrRecognizer.recognize(imagePath: url.path, languages: ["zh-Hant", "en-US"])
            guard session.mode != .idle, !Task.isCancelled else { return }
            let snippet = OCRTextDigest.snippet(from: segments)
            screenTextSummary = snippet.isEmpty ? "畫面文字：（本次無辨識結果）" : "畫面文字：\(snippet)"
        } catch let error as OCRClientError {
            screenTextSummary = "畫面文字：sidecar 未回應（\(error)）"
        } catch {
            screenTextSummary = "畫面文字：未啟用（\(error.localizedDescription)）"
        }
    }

    private static func savePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw OCRClientError.badResponse
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw OCRClientError.badResponse }
    }

    /// 啟動真螢幕擷取：SCShareableContent → SCKFrameProducer → CaptureEngine → 摘要。
    /// 全程 guarded：無 Metal / 缺權限 / SCK 失敗 → 擷取關閉，事件日誌照常運作。
    /// async 啟動期間若已停止觀察（緊急停止）→ 放棄並收掉，避免擷取在 stop 後仍存活（race）。
    private func startCapture() {
        captureSummary = "螢幕擷取：啟動中…"
        captureStartTask = Task { [weak self] in
            guard let self else { return }
            do {
                let content = try await SCShareableContent.current
                guard self.session.mode != .idle, !Task.isCancelled else { return }  // await 期間已停 → 放棄
                guard let display = content.displays.first else {
                    self.captureSummary = "螢幕擷取：找不到顯示器"; return
                }
                let grid = TileGrid(width: display.width, height: display.height)
                let producer = try SCKFrameProducer(grid: grid)
                let engine = CaptureEngine(grid: grid)
                let config = SCStreamConfiguration()
                config.width = display.width
                config.height = display.height
                config.pixelFormat = kCVPixelFormatType_32BGRA
                // 暫用低固定幀率控 CPU（2fps）。真正的解是注意力驅動的自適應幀率
                // （idle 0.2–1fps、活動處短暫拉高，見 CapturePyramid）——列為後續優化步。
                config.minimumFrameInterval = CMTime(value: 1, timescale: 2)
                config.showsCursor = true
                let filter = SCContentFilter(display: display, excludingWindows: [])
                try producer.start(filter: filter, configuration: config)
                guard self.session.mode != .idle, !Task.isCancelled else {   // start 前後可能已停 → 收掉
                    producer.stop(); await engine.stop(); return
                }
                let events = await engine.start(from: producer)
                self.captureProducer = producer
                self.captureEngine = engine
                self.consumeCaptureEvents(events)
            } catch {
                self.captureSummary = "螢幕擷取：未啟用（\(error.localizedDescription)）"
            }
        }
    }

    /// 讀一次焦點、更新 FOCUS/SWITCH，回傳目前焦點元件（供 TYPE 判斷欄位與安全性）。
    @discardableResult
    private func pollFocus(app: String) -> AXFocusedElement? {
        let element = axProvider.focusedElement()
        // 焦點識別用**視窗標題**（fallback: role）。
        // ⚠️ 不可用 element.value——那是欄位內容，終端機每輸出一字就變，會狂噴 FOCUS（step 29 dogfood 實測）。
        let window = element?.windowTitle ?? element?.role ?? ""
        if let event = focusTracker.event(app: app, window: window) {
            let currentFeed = feed
            Task { await currentFeed.record(event) }
        }
        return element
    }

    /// 輸入事件 → 焦點更新 + TYPE/PASTE/SCROLL 劇本事件（純翻譯在 InputEventTranslator）。
    private func handleInput(_ captured: CapturedInput) {
        let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
        // 滑鼠**移動**不做焦點輪詢：它不代表焦點改變，卻是最高頻的事件源（每次 AX 讀取都有成本）。
        // 點擊/拖曳仍輪詢——那是真正可能換焦點的動作（ADR-0006 也以 click 拉注意力峰值）。
        if case .pointer(let signal) = captured, case .move = signal { return }
        let element = pollFocus(app: app)
        let l0: L0Event?
        switch captured {
        case let .scroll(dx, dy):
            l0 = InputEventTranslator.scroll(app: app, deltaX: dx, deltaY: dy)
        case let .keyDown(chars):
            let secure = InputEventTranslator.isSecure(role: element?.role, subrole: element?.subrole)
            l0 = InputEventTranslator.type(field: element?.role ?? "?", character: chars, isSecureField: secure)
        case .pasteShortcut:
            l0 = InputEventTranslator.paste(clipboard: NSPasteboard.general.string(forType: .string) ?? "")
        case .pointer:
            l0 = nil   // 只驅動焦點/注意力，不直接產 L0
        }
        if let l0 {
            let currentFeed = feed
            Task { await currentFeed.record(l0) }
        }
    }

    /// 消費 CaptureEngine 的 dirty-tile 事件流 → 更新選單擷取摘要（協調邏輯；CaptureActivity 已測）。
    /// 真擷取來源 SCKFrameProducer（SCStream + Metal）於 step 18 真機接上，屆時由此方法點亮。
    func consumeCaptureEvents(_ events: AsyncStream<TileEvent>) {
        captureActivity = CaptureActivity()
        captureTask?.cancel()
        captureTask = Task { [weak self] in
            var lastPush = Date.distantPast
            for await event in events {
                guard let self else { return }
                self.captureActivity.record(event)
                let now = Date()
                if now.timeIntervalSince(lastPush) >= 0.25 {   // 選單摘要最多 ~4Hz，避免每 tile 都刷 UI
                    self.captureSummary = self.captureActivity.summary
                    lastPush = now
                }
            }
        }
    }

    private func teardownPipeline() {
        inputTap?.stop()
        inputTap = nil
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceObserver = nil
        }
        streamTask?.cancel()
        streamTask = nil
        captureStartTask?.cancel()   // 中止還在 async 啟動中的擷取（防 stop 後才啟動的 race）
        captureStartTask = nil
        captureTask?.cancel()
        captureTask = nil
        ocrTask?.cancel()
        ocrTask = nil
        screenTextSummary = "畫面文字：未啟用"
        captureProducer?.stop()
        captureProducer = nil
        let dyingEngine = captureEngine
        captureEngine = nil
        Task { await dyingEngine?.stop() }
        captureSummary = "螢幕擷取：未啟用"
        let dying = feed
        Task { await dying.stop() }
    }
}
