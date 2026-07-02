import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CoPartner").font(.headline)
            Text(coordinator.lastStepSummary)
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(2)
            Divider()

            // 即時操作劇本（最近幾行）——「操作時間機器」的畫面。
            Text("操作劇本").font(.caption2).foregroundStyle(.tertiary)
            if coordinator.recentLines.isEmpty {
                Text("（尚無事件）").font(.caption2).foregroundStyle(.tertiary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(coordinator.recentLines.suffix(8).enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption2, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxHeight: 160)
            }
            Divider()

            Button(coordinator.isIdle ? "開始觀察" : "停止觀察") {
                coordinator.toggleObserving()
            }
            Button("立即介入（⌃⌥⌘Space）") { coordinator.triggerIntervention() }
            Divider()
            Button("緊急停止（⌃⌥⌘.）") { coordinator.stopAll() }
                .foregroundStyle(.red)
            Button("結束 CoPartner") { NSApplication.shared.terminate(nil) }
        }
        .padding(14)
        .frame(width: 320)
    }
}
