import SwiftUI
import CoPartnerCore
import ActionExecutor

// 接手 HUD 的浮層內容（🔒 真機目測於 step 53）。
//
// 版面原則來自威脅模型而非美感：使用者要能在**幾秒內**判斷該不該按執行。
// 因此順序是「本地判定的風險與原因」→「實際會執行什麼」→「模型的說法」，
// 而不是反過來——模型的說法最不可信，不該排在最前面影響判斷。
struct TakeoverHUDView: View {
    let presentation: TakeoverHUDPresentation
    let onDecision: (TakeoverHUDPresentation.Decision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if presentation.isPreview { previewBanner }
            header

            // 實際會執行什麼——本地從結構化欄位產生，不是模型的描述。
            VStack(alignment: .leading, spacing: 4) {
                Text("將執行").font(.caption2).foregroundStyle(.tertiary)
                Text(presentation.actionSummary)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)          // 可複製——要能仔細看
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // 模型的說法。明確標示來源不可信：T1 提示注入可以讓它寫得很安撫人。
            if !presentation.modelRationale.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Claude 的說法（僅供參考，可能被畫面內容影響）")
                        .font(.caption2).foregroundStyle(.tertiary)
                    Text(presentation.modelRationale)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Divider()
            buttons
        }
        .padding(16)
        .frame(width: 460)
    }

    /// 除錯預覽的橫幅。**刻意做得刺眼**：預覽浮層和真浮層長得一樣，
    /// 分不出來的話，使用者要嘛把預覽當真的（白緊張），要嘛把真的當預覽（盲按執行）——
    /// 後者直接毀掉確認閘門。所以這條放在最上面、滿版、不可摺疊。
    private var previewBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "eyedropper")
            Text("版面預覽 — 假提議，按任何按鈕都不會執行任何事")
                .font(.caption).bold()
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle().fill(riskColor).frame(width: 10, height: 10)
                Text(presentation.riskLabel).font(.headline).foregroundStyle(riskColor)
                Spacer()
                Text("接手中").font(.caption2).foregroundStyle(.tertiary)
            }
            // 高風險的本地原因——由 RiskClassifier 產生，與模型推理無關。
            // 沒有原因的 high 等於叫使用者盲簽，所以這裡一定要顯示。
            if let reason = presentation.localRiskReason {
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(riskColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            // 主要按鈕的文字依 policy 誠實反映後果（suggestOnly 不會執行）。
            Button(presentation.approveTitle) { onDecision(.approve) }
                .keyboardShortcut(.defaultAction)
                .tint(presentation.risk == .high ? .red : .accentColor)
            Button("略過") { onDecision(.skip) }
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button("停止接手") { onDecision(.stop) }
                .foregroundStyle(.red)
        }
    }

    private var riskColor: Color {
        switch presentation.risk {
        case .low: return .secondary
        case .medium: return .orange
        case .high: return .red
        }
    }
}
