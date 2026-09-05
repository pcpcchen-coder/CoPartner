import SwiftUI

// 版面原則（開發階段：**訊息可見度優先**）：
//
// 1. **按鈕排在最上方**。放底部時，只要下方任何一區長高就會把最後一顆按鈕推出畫面——
//    這在真機上重演了兩次。擺最上方後，按鈕的位置與訊息量完全脫鉤，結構上不可能再被擠掉。
//    改用橫排還順便省下約 110pt 縱向空間（原本 5 顆直排），全部讓給訊息區。
// 2. **訊息區在下方捲動**，且 L1 敘事與操作劇本**各自獨立捲動**——單一捲動會讓你
//    為了看劇本而把 L1 捲出畫面，兩邊無法同時盯。
// 3. **兩區用固定高度**（不是 minHeight、也不是只給 maxHeight）。這兩種都試過且都不對：
//    只給 minHeight 會在內容少時硬撐出空白；只給 maxHeight 則會在內容少時縮成一條縫，
//    連捲動區都看不見。固定高度讓兩區的大小與當下有幾筆內容無關——訊息少時留著空間等，
//    訊息多時就在區內捲動，版面永遠穩定。
struct MenuBarContentView: View {
    @EnvironmentObject var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // MARK: 按鈕區（最上方，永遠可見）
            HStack(spacing: 8) {
                Button(coordinator.isIdle ? "開始觀察" : "停止觀察") {
                    coordinator.toggleObserving()
                }
                Button("介入（⌃⌥⌘Space）") { coordinator.triggerIntervention() }
                // 除錯入口：真執行端接上前，唯一能目視驗證接手浮層的方式（step 54）。
                // 走的是完全獨立的路徑，按下去不會建立任何接手狀態。
                Button("HUD 預覽") { coordinator.previewHUD() }
                // 除錯入口：真雲端傳輸接上前，唯一能驗證執行端 XPC 這條線的方式（step 53.1）。
                // 送的是專屬的 selfTest kind，夾帶不了真動作。
                Button("XPC 自檢") { coordinator.runXPCSelfTest() }
                // 除錯入口：在任何東西真的執行之前，先看到完整的命令與 profile（step 53.4-B）。
                // 送的是專屬的 dryRun kind，service 端那個分支裡沒有任何 spawn 呼叫。
                Button("執行乾跑") { coordinator.runExecutionDryRun() }
                // ⚠️ 這顆會**真的執行**（step 53.5 驗收用）。送的是本地合成提議，
                // 但走的是與真提議完全相同的路徑——風險分級、HUD 確認、token、沙箱一個不少。
                Button("執行測試") { coordinator.runExecutionSmokeTest() }
                    .tint(.orange)
                // 除錯入口：UI 動作在真的能動之前，先看到「會落在哪裡、那裡有什麼」
                // （step 53.6-B）。`UIActionPerformer.dryRun` 裡沒有任何 post 呼叫。
                Button("UI 乾跑") { coordinator.runUIDryRun() }
                // 除錯入口：在任何一張圖離開這台機器之前，**親眼看到那張圖**（step 58）。
                // 延遲 4 秒擷取——打開選單會讓 CoPartner 變成最前景，而它自己在黑名單上。
                Button("截圖乾跑") { coordinator.runScreenshotDryRun() }
                // ⚠️ 這顆會**真的送出 UI 事件**（step 53.6-C 驗收用）。
                // 送的是捲動：看得見、可逆、不需要座標就能觀察到效果。
                // 走的路徑與真提議完全相同——風險分級、HUD 確認、token 一個不少。
                Button("UI 測試") { coordinator.runUISmokeTest() }
                    .tint(.orange)
                SettingsLink { Text("熱鍵…") }
                Spacer()
                Button("緊急停止") { coordinator.stopAll() }
                    .foregroundStyle(.red)
                Button("結束") { NSApplication.shared.terminate(nil) }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            // MARK: 訊息區
            VStack(alignment: .leading, spacing: 8) {
                Text(coordinator.lastStepSummary)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2)
                Group {
                    Text(coordinator.captureSummary).lineLimit(1)
                    Text(coordinator.screenTextSummary).lineLimit(2)
                    Text(coordinator.takeoverSummary).lineLimit(1)
                    // 自檢輸出是**驗收證據**，不是狀態列裝飾——寧可佔三行也不能截斷。
                    // `fixedSize(vertical:)` 才會真的讓它長高；只給 lineLimit 的話
                    // 容器仍會把它壓成一行再加省略號（真機上就這樣吃掉了關鍵欄位兩次）。
                    // 長報告一律寫檔案、選單只留一句判定與路徑（UI 乾跑的完整報告
                    // 在真機上就被這裡截掉過，而被截掉的正是最該看的那兩行）。
                    // 這裡因此只需容得下「判定 + 路徑」。
                    Text(coordinator.xpcSummary)
                        .lineLimit(6)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)      // 可複製，方便貼回報告
                    Text(coordinator.localModelSummary).lineLimit(1)
                    // 記憶體診斷（handoff §7.6.6）。每次打開這個選單就是一次取樣，
                    // 所以放在這裡不只是顯示——這一行的存在本身就是量測動作。
                    Text(coordinator.memorySummary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    // 階段軌跡另外一行：它回答的是「閒置的底線會不會一輪比一輪高」，
                    // 而那是唯一能分辨「留著不放的快取」與「真的在漏」的觀察。
                    Text(coordinator.memoryTrail)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    // 完整曲線在檔案裡。路徑要看得見且**可複製**——
                    // 否則使用者得先問「那個檔在哪」才能把資料交出來。
                    Text("記憶體日誌：\(coordinator.memoryLogPath)")
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .font(.caption2).foregroundStyle(.tertiary)

                Divider()

                // L1 敘事（step 42）：一行行低階事件 → 「一句話 step + 推測目標」。
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
                            ForEach(Array(coordinator.l1Steps.suffix(40).reversed())) { step in
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
                .frame(height: 240)

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
                            ForEach(Array(coordinator.recentLines.suffix(150).reversed().enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(.caption2, design: .monospaced))
                                    .lineLimit(1).truncationMode(.tail)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .frame(height: 350)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
        // 1080：又多一顆按鈕（截圖乾跑）。按鈕被擠出畫面真機上重演過兩次，寧可先留寬。
        .frame(width: 1080)
        // 打開選單 ＝ 取一個記憶體樣本。用 onAppear 而不是定時器：見 AppCoordinator。
        .onAppear { coordinator.sampleMemory() }
    }
}
