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

            // 即時操作劇本（最新在上）——「操作時間機器」的畫面。
            Text("操作劇本").font(.caption2).foregroundStyle(.tertiary)
            ScrollView {
                if coordinator.recentLines.isEmpty {
                    Text("（尚無事件；按「開始觀察」後操作看看）")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(coordinator.recentLines.suffix(80).reversed().enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption2, design: .monospaced))
                                .lineLimit(1).truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .frame(minHeight: 260, maxHeight: 360)

            Divider()
            Button(coordinator.isIdle ? "開始觀察" : "停止觀察") {
                coordinator.toggleObserving()
            }
            Button("立即介入（⌃⌥⌘Space）") { coordinator.triggerIntervention() }
            SettingsLink { Text("設定熱鍵…") }
            Divider()
            Button("緊急停止") { coordinator.stopAll() }
                .foregroundStyle(.red)
            Button("結束 CoPartner") { NSApplication.shared.terminate(nil) }
        }
        .padding(14)
        .frame(width: 460)
    }
}
