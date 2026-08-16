import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CoPartner").font(.headline)
            Text(coordinator.lastStepSummary)
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(2)
            Text(coordinator.captureSummary)
                .font(.caption2).foregroundStyle(.tertiary)
                .lineLimit(1)
            Text(coordinator.screenTextSummary)
                .font(.caption2).foregroundStyle(.tertiary)
                .lineLimit(2)
            Text(coordinator.takeoverSummary)
                .font(.caption2).foregroundStyle(.tertiary)
                .lineLimit(2)
            Text(coordinator.localModelSummary)
                .font(.caption2).foregroundStyle(.tertiary)
                .lineLimit(1)
            Divider()

            // L1 敘事（step 42）：把一行行低階事件升級成「一句話 step + 推測目標」。
            // 前綴 [層級 延遲ms/觸發原因] 讓 M4 驗收可直接讀，不必翻 Console。
            Text("理解中的動作").font(.caption2).foregroundStyle(.tertiary)
            Text(coordinator.l1Summary)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(3)
            if !coordinator.l1Steps.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(coordinator.l1Steps.suffix(12).reversed())) { step in
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(step.app)・\(step.category)\(step.openLoop ? "・進行中" : "")")
                                    .font(.caption2).foregroundStyle(.tertiary)
                                Text(step.whatHappened)
                                    .font(.caption2)
                                    .lineLimit(2)
                                Text("↳ \(step.inferredGoal)")
                                    .font(.caption2).foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(minHeight: 90, maxHeight: 150)
            }
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
            .frame(minHeight: 150, maxHeight: 220)   // 讓位給 L1 敘事區，整個選單才不會過高

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
