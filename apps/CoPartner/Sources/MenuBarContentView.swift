import SwiftUI

// 版面原則：**按鈕永遠可見**。
// 先前把狀態列 + L1 敘事 + 操作劇本全放在同一個會長高的 VStack、內含兩個各自帶
// minHeight 的 ScrollView，總高度被撐到超過選單可用空間，按鈕被擠出畫面點不到
// （真機 dogfood 實測）。改為：所有資訊收進**單一**外層 ScrollView（內層列表不再
// 各自捲動，避免巢狀捲動互搶手勢），按鈕放在 ScrollView 外面固定於底部。
struct MenuBarContentView: View {
    @EnvironmentObject var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("CoPartner").font(.headline)
                    Text(coordinator.lastStepSummary)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(2)
                    Group {
                        Text(coordinator.captureSummary).lineLimit(1)
                        Text(coordinator.screenTextSummary).lineLimit(2)
                        Text(coordinator.takeoverSummary).lineLimit(2)
                        Text(coordinator.localModelSummary).lineLimit(1)
                    }
                    .font(.caption2).foregroundStyle(.tertiary)

                    Divider()

                    // L1 敘事（step 42）：把一行行低階事件升級成「一句話 step + 推測目標」。
                    // 前綴 [層級 延遲ms/觸發原因] 讓 M4 驗收可直接讀，不必翻 Console。
                    Text("理解中的動作").font(.caption2).foregroundStyle(.tertiary)
                    Text(coordinator.l1Summary)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(3)
                    // 只列最近 5 筆：更早的在記憶層裡，選單不是歷史瀏覽器。
                    ForEach(Array(coordinator.l1Steps.suffix(5).reversed())) { step in
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

                    Divider()

                    // 即時操作劇本（最新在上）——「操作時間機器」的畫面。
                    Text("操作劇本").font(.caption2).foregroundStyle(.tertiary)
                    if coordinator.recentLines.isEmpty {
                        Text("（尚無事件；按「開始觀察」後操作看看）")
                            .font(.caption2).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(coordinator.recentLines.suffix(40).reversed().enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(.caption2, design: .monospaced))
                                    .lineLimit(1).truncationMode(.tail)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 8)
            }
            .frame(maxHeight: 420)   // 資訊區有上限；超出就在區內捲動，不再把按鈕往下推

            Divider()

            VStack(alignment: .leading, spacing: 6) {
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
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 460)
    }
}
