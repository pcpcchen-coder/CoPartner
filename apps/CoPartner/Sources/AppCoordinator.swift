import SwiftUI
import Combine
import AppKit
import KeyboardShortcuts
import CoreVideo
import CoreMedia
@preconcurrency import ScreenCaptureKit
import CoPartnerCore
import CaptureEngine
import ScriptNarrator
import MemoryStore
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

    // 局部 OCR（step 29）：截焦點畫面 → **macOS Vision 直接辨識** → 摘要。
    // 不經 sidecar：日常使用零外部服務依賴，使用者只要開 app（sidecar 保留給 /vlm 視覺語意）。
    private let ocrRecognizer = VisionTextRecognizer()
    private var ocrTask: Task<Void, Never>?
    private lazy var ocrBlacklist = CaptureBlacklist(ownBundleID: Bundle.main.bundleIdentifier ?? "com.copartner.app")

    // L1 本地敘事（step 42）：L0 劇本行 → NarrationLadder → ActionStep → 熱環 + 記憶。
    // 階梯每次 rollup 重建（見 narrationTick）；模型不可用時 fm 層為 nil → 自動走規則式。
    @Published private(set) var l1Summary: String = "本地敘事：未啟用"
    @Published private(set) var l1Steps: [ActionStep] = []
    @Published private(set) var localModelSummary: String = LocalNarrationAvailability.frameworkAbsent.displayText
    private var ladder = NarrationLadder()
    private var rollupScheduler = L1RollupScheduler()
    private var hotBuffer = L1HotBuffer()
    private let memory = MemoryStore()
    private var rollupTask: Task<Void, Never>?
    private var lastRollupApp: String?
    /// 最近一次觀察到的前景 app；rollup 以它與 `lastRollupApp` 的差異判斷 step 邊界。
    private var currentApp: String?

    // 接手鏈（step 49）：世代時鐘為 token 作廢的單一權威（威脅 I7）。
    @Published private(set) var takeoverSummary: String = "接手：未啟動"
    private let handoffGeneration = HandoffGeneration()
    private var takeoverModel: TakeoverSessionModel?
    private var handoffTask: Task<Void, Never>?

    // 接手 HUD（step 53）：常駐浮層顯示提議 → Approve/Skip/Stop。
    private let hudPanel = TakeoverHUDPanel()
    private let riskClassifier = RiskClassifier()
    /// 每次接手依當次 contract 重建——`SandboxPolicy` 來自 `TakeoverContract.allowedTools`，
    /// 是 per-handoff 的值，不能在 init 就固定死。
    private var actionExecutor: ActionExecutor?
    /// 等待使用者按鍵的 continuation。
    ///
    /// ⚠️ **中止時務必 resume**：CheckedContinuation 沒被 resume 就走掉會洩漏
    /// （Swift 執行期會抱怨，而且那條 handoff task 永遠卡住不會結束）。
    /// 所以 `abortHandoff` 一定要把它以 `.stop` 收掉——見該方法。
    private var pendingDecision: CheckedContinuation<TakeoverHUDPresentation.Decision, Never>?
    private let cloudRouter = CloudRouter()   // 無 transport：真雲端傳輸 🔒 step 53

    // 執行端 XPC（step 55 ①）：主 app ↔ service 的連線。
    // service 目前**沒有執行能力**，回覆一律是「收到但沒做」→ 轉成 throw，不假裝成功。
    private let xpcPerformer = XPCActionPerformer()
    @Published private(set) var xpcSummary: String = "執行端：未檢測"

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
        let now = Date()
        // 真 L1 取材（step 42 接線）：熱環裡時間窗內的 ActionStep 就是劇本主體。
        // EnvelopeBuilder 自己會截到 maxRecentSteps，這裡不預先裁。
        let steps = hotBuffer.recentSteps(now: now)
        // open loop 優先用 L1 的推測——「使用者正在做什麼」比最後一行原始事件更有資訊量；
        // 還沒有任何 step（剛開始觀察）才退回 L0 末行。
        let openLoop = steps.last.map { "\($0.whatHappened)（推測目標：\($0.inferredGoal)）" }
            ?? lines.last ?? "（無最近操作）"
        let envelope = EnvelopeBuilder().build(
            now: now,
            steps: steps,
            sessionSummary: lines.suffix(10).joined(separator: "\n"),
            openLoop: openLoop,
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
            // executor 依**這次的 contract** 建：allowedTools 是 per-handoff 的值（T4）。
            // 共用同一個世代時鐘 → Stop 一撥，在途 token 全部作廢（I7 單一權威）。
            // performer 接上 XPC（step 55 ①）。service 尚無執行能力 → 回「收到但沒做」，
            // 客戶端轉成 throw .notWired，HUD 因此顯示「未執行」而非靜默假裝成功。
            // generation 只是稽核關聯用；真正的世代驗證在 execute 裡（I7）。
            let performer = xpcPerformer
            let generation = handoffGeneration.current
            actionExecutor = ActionExecutor(
                clock: handoffGeneration,
                policy: .from(contract: cleanEnvelope.takeover),
                allowlist: Self.defaultPathAllowlist(),
                performer: { action in
                    try await performer.perform(action, generation: generation)
                })
            let router = cloudRouter
            handoffTask = Task { [weak self] in
                do {
                    let stream = await router.handoff(cleanEnvelope,
                                                      systemPrompt: "CoPartner takeover",
                                                      referencePrefix: "")
                    for try await proposal in stream {
                        guard let self else { return }
                        let keepGoing = await self.handle(proposal: proposal)
                        if !keepGoing { return }        // 使用者按了停止接手
                    }
                    guard let self else { return }
                    self.hudPanel.hide()
                    self.takeoverModel?.complete()
                    self.takeoverSummary = "接手：完成"
                    self.session.endIntervention()
                } catch {
                    guard let self else { return }
                    self.hudPanel.hide()
                    let message: String
                    switch error as? HandoffError {
                    case .noTransport:      message = "雲端傳輸尚未接線（step 53）"
                    case .noRequestBuilder: message = "交棒請求未設定顯示器尺寸（step 53）"
                    case .none:             message = error.localizedDescription
                    }
                    self.takeoverSummary = "接手：\(message)"
                    self.takeoverModel = nil
                    self.session.endIntervention()       // 失敗 → 回觀察，事件日誌不中斷
                }
            }
        }
    }

    // MARK: - 接手 HUD 迴圈（step 53）

    /// 處理一個提議。回傳「是否繼續接手」——false 代表使用者按了停止。
    ///
    /// 流程刻意是：**本地風險分級 → 狀態機決定要不要問人 → HUD → 執行**。
    /// 風險分級在最前面且與模型推理無關，是 T1 提示注入的最後防線。
    private func handle(proposal: ProposedAction) async -> Bool {
        guard var model = takeoverModel else { return false }
        let risk = riskClassifier.classify(proposal)
        takeoverSummary = "接手提議：\(proposal.kind.summary)"

        // autoBounded + low + 未達上限 → 狀態機自動核並回 token；其餘回 nil、要問人。
        if let token = model.receive(proposal, risk: risk) {
            takeoverModel = model
            await execute(proposal, token: token)
            return true
        }
        takeoverModel = model

        let presentation = TakeoverHUDPresentation.make(action: proposal,
                                                        risk: risk,
                                                        policy: model.policy,
                                                        classifier: riskClassifier)
        let decision = await awaitDecision(showing: presentation)

        guard var m = takeoverModel else { return false }
        switch decision {
        case .approve:
            let token = m.approve()      // suggestOnly 回 nil——按了也不執行
            takeoverModel = m
            if let token {
                await execute(proposal, token: token)
            } else {
                takeoverSummary = "接手：僅建議，未執行 \(proposal.kind.summary)"
            }
            return true
        case .skip:
            m.skip()
            takeoverModel = m
            takeoverSummary = "接手：略過 \(proposal.kind.summary)"
            return true
        case .stop:
            m.stop()                     // 內含 generation.abort()——在途 token 全失效
            takeoverModel = m
            hudPanel.hide()
            takeoverSummary = "接手：已停止"
            session.endIntervention()
            return false
        }
    }

    // MARK: - HUD 版面預覽（step 54，除錯入口）

    /// 用假提議叫出浮層，目視驗證版面 / 位置 / 按鈕 / 跨 app 浮動行為。
    /// 真執行端（XPC + sandbox-exec）接上之前，這是唯一能看到 HUD 的方式。
    ///
    /// **這條路徑刻意完全繞開接手狀態機**：不建 `takeoverModel`、不建 `actionExecutor`、
    /// 不碰 `pendingDecision`、不動世代時鐘。決定回呼只做「關掉浮層」一件事。
    /// 預覽若能走進 `handle(proposal:)`，一顆除錯按鈕就成了繞過確認閘門的後門。
    ///
    /// 接手進行中時**拒絕預覽**：浮層只有一個，蓋掉真提議會讓使用者對著假的按下去，
    /// 而真的那筆還卡在 `pendingDecision` 等回應（連 continuation 也會被搞混）。
    func previewHUD() {
        guard takeoverModel == nil, pendingDecision == nil else {
            takeoverSummary = "接手：進行中，預覽已略過（避免蓋掉真提議）"
            return
        }
        hudPanel.show(.previewFixture()) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.hudPanel.hide()               // 三顆按鈕在預覽下都只是關掉
                self?.takeoverSummary = "接手：未啟動（版面預覽已關閉）"
            }
        }
        takeoverSummary = "接手：版面預覽中（假提議，不會執行）"
    }

    /// 執行端 XPC 自檢（step 55 ①，除錯入口）。
    ///
    /// 真雲端傳輸接上之前沒有辦法產生真提議，也就沒有辦法驗證這條線——
    /// 同 HUD 預覽的處境。送的是**專屬的 `.selfTest` kind**，不是借用一個 shell 動作，
    /// 所以第 ④ 段接上真執行之後，這個入口仍然不可能夾帶真動作。
    ///
    /// 報告刻意顯示 pid 與 euid：「有回應」不等於「跑在另一個程序」，
    /// 這件事要看到數字才算驗過。
    func runXPCSelfTest() {
        xpcSummary = "執行端：檢測中…"
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.xpcPerformer.selfTest()
                let report = result.report
                let ownPID = ProcessInfo.processInfo.processIdentifier
                let separate = report.servicePID != ownPID ? "獨立程序" : "⚠️ 同一程序"
                self.xpcSummary = "執行端：已連線・\(separate)"
                    + "（service pid \(report.servicePID) / app pid \(ownPID)）"
                    + "・euid \(report.serviceEUID)"
                    + "・會執行動作：\(report.willExecuteActions ? "是" : "否")"
                    + "・驗呼叫者：\(report.callerVerificationDetail)"
                    + "・驗 service：\(result.serviceVerification)"
            } catch {
                self.xpcSummary = "執行端：連不上（\(error)）"
            }
        }
    }

    /// 顯示 HUD 並等使用者按鍵。
    private func awaitDecision(showing presentation: TakeoverHUDPresentation) async
        -> TakeoverHUDPresentation.Decision {
        await withCheckedContinuation { continuation in
            pendingDecision = continuation
            hudPanel.show(presentation) { [weak self] decision in
                MainActor.assumeIsolated { self?.resolveDecision(decision) }
            }
        }
    }

    /// 收下使用者的決定並喚醒等待中的 handoff task。**只會 resume 一次**——
    /// 先取出再清空，避免連按兩下造成重複 resume（那會直接 crash）。
    private func resolveDecision(_ decision: TakeoverHUDPresentation.Decision) {
        guard let continuation = pendingDecision else { return }
        pendingDecision = nil
        continuation.resume(returning: decision)
    }

    /// 執行一個已核准的動作。真執行端未接時 throw `.notWired`，HUD 誠實顯示而非假裝成功。
    private func execute(_ action: ProposedAction, token: ApprovalToken) async {
        guard let executor = actionExecutor else { return }
        do {
            try await executor.execute(action, token: token)
            takeoverSummary = "接手：已執行 \(action.kind.summary)"
        } catch {
            let reason: String
            switch error as? ExecutionError {
            case .notWired:
                reason = "XPC 已連線，但 service 尚無執行能力（第 ① 段骨架的預期結果）"
            case .xpcUnavailable(let detail):
                reason = "XPC 連線問題：\(detail)"
            case .notSandboxable(let summary):
                reason = "UI 類動作不走沙箱路徑，主程序內執行端待接（\(summary)）"
            default:
                reason = String(describing: error)
            }
            takeoverSummary = "接手：未執行 \(action.kind.summary) — \(reason)"
        }
        takeoverModel?.finishExecution()
    }

    /// 路徑白名單（I5）。目前給保守的預設值；使用者可設定的版本待做。
    private static func defaultPathAllowlist() -> PathAllowlist {
        let home = NSHomeDirectory()
        return PathAllowlist(allowedRoots: ["\(home)/Documents", "\(home)/Desktop"])
    }

    /// 中止接手鏈：取消串流、作廢世代 token（I7）、回觀察/停止。冪等。
    private func abortHandoff(reason: String) {
        handoffTask?.cancel()
        handoffTask = nil
        // ⚠️ 先把等待中的 HUD 決定以 .stop 收掉，再取消 task。
        // CheckedContinuation 沒被 resume 就走掉會洩漏——執行期會抱怨，而且那條
        // handoff task 會永遠停在 await 不結束（緊急停止就變成停不掉）。
        resolveDecision(.stop)
        hudPanel.hide()
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
                // 餵新穎度偵測器（不能用行數差 — 見 L1RollupScheduler 的說明）。
                self.rollupScheduler.observe(snapshot: lines, at: Date())
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
        startOCRLoop()   // 局部 OCR（走 macOS Vision；失敗則不影響事件日誌與擷取）
        startNarrationLoop()   // L1 本地敘事（模型不可用則降級規則式，永不中斷）
    }

    // MARK: - L1 本地敘事（step 42）

    /// 組裝敘事階梯 + 預熱模型 + 啟動 rollup 迴圈。
    /// 全程 guarded：無 FoundationModels / 未開 Apple Intelligence → fm 層為 nil，
    /// 階梯自動降到規則式，敘事照樣有輸出（§5：降級但不中斷）。
    private func startNarrationLoop() {
        // 視窗 20 行（預設值）：行數越多 prompt 越長、模型也越容易寫得落落長，
        // 兩者都直接推高延遲。一個 step 本來就只該涵蓋一小段操作。
        rollupScheduler = L1RollupScheduler(windowLines: 20)
        hotBuffer = L1HotBuffer()
        lastRollupApp = nil
        l1Steps = []
        l1Summary = "本地敘事：等待第一個 step…"

        localModelSummary = LocalNarrationEnvironment.availability.displayText

        // 階梯只建一次並長期存活。narrator 從日誌行推導 app（不再 init 綁定），
        // 因此不需要每次 rollup 重建——重建會把 prewarm 過的狀態一起丟掉。
        // Qwen MLX 層需 sidecar 起著；日常使用不預設啟動（見交接文件 §5），故不掛。
        ladder = NarrationLadder(fm: LocalNarrationEnvironment.makeFoundationModelsBackend(app: "未知"),
                                 qwen: nil,
                                 rule: RuleBasedNarrator())

        rollupTask = Task { [weak self] in
            // 預熱：把 3B 權重先載進記憶體，否則第一個 step 會吃到冷啟動延遲。無框架時是 no-op。
            await LocalNarrationEnvironment.prewarm()
            while !Task.isCancelled {
                guard let self, self.session.mode != .idle else { return }
                await self.narrationTick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// 一次 rollup 判斷：該捲就把最近的 L0 行餵階梯，產 L1 step 存進熱環 + 記憶。
    private func narrationTick() async {
        let now = Date()
        let appChanged = (currentApp != nil && currentApp != lastRollupApp && lastRollupApp != nil)
        guard let trigger = rollupScheduler.evaluate(now: now, appChanged: appChanged) else { return }

        let window = rollupScheduler.window(of: recentLines)
        // availability 每次重查：使用者可能在觀察途中開/關 Apple Intelligence
        // （runbook M4 第 4 步就是要驗這個切換不中斷）。
        let availability = LocalNarrationEnvironment.availability
        localModelSummary = availability.displayText

        // 用 ContinuousClock 而非 Date 差：後者是掛鐘時間，會被 NTP 校時扭曲，
        // 拿來量幾百 ms 的延遲不可靠。
        let started = ContinuousClock.now
        let result = await ladder.narrateReportingTier(window,
                                                       fmAvailable: availability.canUseFoundationModels,
                                                       qwenReachable: false)
        let elapsed = ContinuousClock.now - started
        // Duration.components 把秒與次秒分開；只取 attoseconds 會讓 >1s 的延遲顯示成錯的小數字。
        let elapsedMS = Int(elapsed.components.seconds * 1000
                            + elapsed.components.attoseconds / 1_000_000_000_000_000)
        rollupScheduler.complete()
        lastRollupApp = currentApp

        guard session.mode != .idle, !Task.isCancelled else { return }

        let step = result.step
        hotBuffer.append(step, at: now)
        l1Steps = hotBuffer.recentSteps(now: now)
        // 延遲同時顯示在選單：M4 驗收要量「單次 L1 rollup 延遲」，
        // 讓使用者直接讀數字，不必去翻 Console log。
        l1Summary = "[\(result.tier.displayLabel) \(elapsedMS)ms/\(trigger.rawValue)] "
            + "\(step.whatHappened) — \(step.inferredGoal)"
        await memory.insert(step: step)
        // 把已存筆數也顯示出來：否則「有沒有真的進記憶層」在真機上完全看不出來，
        // 而 M4 驗收要的就是這條鏈確實接上了。
        let stored = await memory.count
        localModelSummary = availability.displayText + "・記憶 \(stored) 筆"
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
            let full = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

            // 只 OCR 焦點區（§B.8）：整螢幕 OCR 會混入選單列/他 app 文字，且違反 M2 吞吐指標。
            // 無有效焦點框 → 本次略過（不做全螢幕 OCR）。
            let focusFrame = axProvider.focusedElement()?.frame
            guard let crop = OCRCropPlanner.cropRect(focusFrame: focusFrame,
                                                     screenWidth: display.width,
                                                     screenHeight: display.height) else {
                screenTextSummary = "畫面文字：（無焦點區，略過）"
                return
            }
            // CGImage 座標可能因 Retina 而與點座標不同比例——依實際像素寬換算縮放。
            let scale = CGFloat(full.width) / CGFloat(display.width)
            let pixelCrop = CGRect(x: crop.minX * scale, y: crop.minY * scale,
                                   width: crop.width * scale, height: crop.height * scale)
            guard let image = full.cropping(to: pixelCrop) else {
                screenTextSummary = "畫面文字：（裁切失敗）"
                return
            }

            // 直接把裁好的影像餵 Vision——不落地存 PNG、不走 HTTP。
            let segments = try await ocrRecognizer.recognize(image: image, languages: ["zh-Hant", "en-US"])
            guard session.mode != .idle, !Task.isCancelled else { return }
            let ratio = OCRCropPlanner.areaRatio(cropRect: crop,
                                                 screenWidth: display.width, screenHeight: display.height)
            let pct = Int((ratio * 100).rounded())   // M2 吞吐指標：目標 ≤ ~20%
            // Vision 的 boundingBox 是左下原點——講明慣例，否則摘要會上下顛倒。
            let snippet = OCRTextDigest.snippet(from: segments, origin: .bottomLeft)
            screenTextSummary = snippet.isEmpty
                ? "畫面文字：（本次無辨識結果，焦點區 \(pct)%）"
                : "畫面文字[\(pct)%]：\(snippet)"
        } catch {
            screenTextSummary = "畫面文字：未啟用（\(error.localizedDescription)）"
        }
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
        currentApp = app        // L1 rollup 以 app 變動當 step 邊界（見 narrationTick）
        let element = axProvider.focusedElement()
        // 焦點識別用**視窗標題**（fallback: role）。
        // ⚠️ 不可用 element.value——那是欄位內容，終端機每輸出一字就變，會狂噴 FOCUS（step 29 dogfood 實測）。
        //
        // app 名稱來自 NSWorkspace、視窗標題來自 AX，兩條是獨立來源，切換瞬間會不同步。
        // 先用焦點元件的擁有者對帳，對不上就當作沒讀到標題（step 54 dogfood 第二輪）。
        let axOwnerApp = element?.ownerPID
            .flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName }
        let window = FocusChangeTracker.reconciledWindow(frontmostApp: app,
                                                         axOwnerApp: axOwnerApp,
                                                         axWindowTitle: element?.windowTitle,
                                                         axRoleFallback: element?.role)
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
        rollupTask?.cancel()
        rollupTask = nil
        l1Summary = "本地敘事：未啟用"
        // l1Steps / hotBuffer 刻意**不清空**：停止觀察後劇本仍要看得到（操作時間機器），
        // 下次 startNarrationLoop 才重置。
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
