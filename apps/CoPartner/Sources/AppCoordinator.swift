import SwiftUI
import Combine
import AppKit
import CaptureEngine
import ScriptNarrator
// 串接各子系統的協調者（🔒 真機膠水：實際觀察行為於 step 10 dogfood 驗收）。
// 可測邏輯放在 CoPartnerKit（EventLogFeed / FocusChangeTracker），此處只做接線與顯示。

@MainActor
final class AppCoordinator: ObservableObject {
    enum Mode { case idle, observing, intervening }
    @Published private(set) var mode: Mode = .idle
    @Published var lastStepSummary: String = "尚未開始觀察"
    @Published private(set) var recentLines: [String] = []

    private let feed = EventLogFeed(capacity: 300)
    private var focusTracker = FocusChangeTracker()
    private let axProvider = SystemAXFocusProvider()
    private var inputTap: InputEventTap?
    private var workspaceObserver: NSObjectProtocol?
    private var streamTask: Task<Void, Never>?

    var statusIcon: String {
        switch mode {
        case .idle: return "eye.slash"
        case .observing: return "eye"
        case .intervening: return "wand.and.stars"
        }
    }

    func toggleObserving() {
        mode == .idle ? startObserving() : stopAll()
    }

    private func startObserving() {
        guard mode == .idle else { return }
        mode = .observing
        lastStepSummary = "觀察中…"

        // 訂閱 feed 即時快照（Task 繼承 MainActor）→ 更新 UI。
        streamTask = Task { [weak self] in
            guard let self else { return }
            for await lines in self.feed.updates {
                self.recentLines = lines
                if let last = lines.last { self.lastStepSummary = last }
            }
        }

        // NSWorkspace 應用切換：免權限、最可靠的骨架訊號。
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let name = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.localizedName ?? "?"
            Task { @MainActor in self?.observeFocus(app: name) }
        }

        // 輸入事件 tap：需 Input Monitoring；失敗（缺權限）則僅靠 NSWorkspace。
        let tap = InputEventTap { [weak self] _ in
            Task { @MainActor in
                let name = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
                self?.observeFocus(app: name)
            }
        }
        _ = tap.start()
        inputTap = tap
    }

    /// 讀當前焦點，交給 FocusChangeTracker 決定是否產生一個 L0 事件。
    private func observeFocus(app: String) {
        let window = axProvider.focusedElement()?.value ?? ""
        if let event = focusTracker.event(app: app, window: window) {
            Task { await feed.record(event) }
        }
    }

    /// 緊急停止 / 停止觀察：拆掉所有觀察來源並結束串流（step 9 併入介入中止）。
    func stopAll() {
        guard mode != .idle else { return }
        mode = .idle
        inputTap?.stop()
        inputTap = nil
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceObserver = nil
        }
        streamTask?.cancel()
        streamTask = nil
        Task { await feed.stop() }
        lastStepSummary = "已停止觀察"
    }

    func triggerIntervention() { /* step 49：打包 ContextEnvelope → CloudRouter.handoff */ }
}
