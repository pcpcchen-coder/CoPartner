import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CoPartner").font(.headline)
            Text(coordinator.lastStepSummary)
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(3)
            Divider()
            Button(coordinator.mode == .idle ? "開始觀察" : "停止觀察") {
                coordinator.toggleObserving()
            }
            Button("立即介入（⌃⌥⌘Space）") { coordinator.triggerIntervention() }
            Divider()
            Button("緊急停止（⌃⌥⌘.）") { coordinator.mode = .idle }
                .foregroundStyle(.red)
            Button("結束 CoPartner") { NSApplication.shared.terminate(nil) }
        }
        .padding(14)
        .frame(width: 280)
    }
}
