import SwiftUI
import Combine
// 串接各子系統的協調者。實作待各 milestone 完成。

@MainActor
final class AppCoordinator: ObservableObject {
    enum Mode { case idle, observing, intervening }
    @Published var mode: Mode = .idle
    @Published var lastStepSummary: String = "尚未開始觀察"

    var statusIcon: String {
        switch mode {
        case .idle: return "eye.slash"
        case .observing: return "eye"
        case .intervening: return "wand.and.stars"
        }
    }

    // TODO(M0): 啟動 CaptureEngine
    // TODO(M2.5): 啟動 ScriptNarrator（L0）
    // TODO(M3): 接上 KeyboardShortcuts 全域熱鍵 → 觸發 handoff
    func toggleObserving() { mode = (mode == .idle) ? .observing : .idle }
    func triggerIntervention() { /* TODO: 打包 ContextEnvelope → CloudRouter.handoff */ }
}
