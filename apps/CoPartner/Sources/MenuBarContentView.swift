import SwiftUI

// 版面原則：**觀察面積要大，而且按鈕永遠可見**——兩者是獨立的問題，分開解。
//
// 按鈕出鏡的真正原因不是內容太多，而是按鈕當初和捲動區放在同一個會長高的 VStack 裡，
// 內容一多就把按鈕往下推出畫面。所以按鈕放在所有捲動區**外面**、固定於底部；
// 這樣不論劇本有幾行、L1 有幾筆，按鈕的位置都不動。
//
// 觀察面積則靠「加寬視窗 + 兩個各自獨立捲動的區塊」處理：L1 敘事與操作劇本各自捲動、
// 互不干擾，兩邊都能同時看到（單一外層捲動會讓你為了看劇本而把 L1 捲出畫面）。
struct MenuBarContentView: View {
    @EnvironmentObject var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
            ScrollView {
                if coordinator.l1Steps.isEmpty {
                    Text("（尚無 step；累積約 12 筆操作或切換 app 後產生）")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(coordinator.l1Steps.suffix(20).reversed())) { step in
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(step.app)・\(step.category)\(step.openLoop ? "・進行中" : "")")
                                    .font(.caption2).foregroundStyle(.tertiary)
                                Text(step.whatHappened)
                                    .font(.caption2)
                                    .lineLimit(2)
                                Text("↳ \(step.inferredGoal)")
                                    .font(.caption2).foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .frame(minHeight: 170, maxHeight: 210)

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
            .frame(minHeight: 260, maxHeight: 320)

            Divider()

            // 按鈕區：刻意放在所有 ScrollView 之外，內容再多也不會把它推出畫面。
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
        }
        .padding(14)
        .frame(width: 620)   // 加寬：長劇本行少換行、L1 敘事一行放得下，等於變相多出縱向空間
    }
}
