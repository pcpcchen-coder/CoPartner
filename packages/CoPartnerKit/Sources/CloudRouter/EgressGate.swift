import Foundation
import CoPartnerCore
// 設計：sandbox-threat-model.md 威脅 T6 / 不變式 I6（PII 出境硬牆）+ v2.1 §6（出境前洗 PII）。
// 出境前最後一道：逐欄位掃描 envelope；PIPL 命中（上海個資/敏感）→ 整包拒出；其餘欄位過 scrubber 遮罩。
// scrubber 注入（app 層接 PIIMasker），CI 用假 scrubber/detector 驗閘門邏輯。
//
// step 58 補上第四件事：**截圖**。在那之前這個閘門完全沒看過 `focusSnapshotJPEGBase64`，
// 見 `check(_:screenshot:)` 的說明——那是接上真雲端前必須先關上的洞。

public protocol PIIScrubbing: Sendable {
    func scrub(_ text: String) -> (clean: String, foundPII: Bool)
}

public enum EgressDecision: Sendable {
    case allow(ContextEnvelope)     // 已遮罩、可出境
    case blocked(reason: String)    // PIPL 命中的欄位名；整包不出境
}

public struct EgressGate: Sendable {
    private let scrubber: any PIIScrubbing
    private let piplDetector: @Sendable (String) -> Bool

    public init(scrubber: any PIIScrubbing, piplDetector: @escaping @Sendable (String) -> Bool) {
        self.scrubber = scrubber
        self.piplDetector = piplDetector
    }

    /// 出境前最後一道。
    ///
    /// ⚠️ **`screenshot` 預設是 `.withhold`，而且沒有第二種預設值。**
    ///
    /// 這個參數在 step 58 加上之前，`focusSnapshotJPEGBase64` 根本沒被這個方法看過——
    /// 只掃文字欄位，然後 `var out = envelope` 把圖原封不動帶出去。塞一張圖進 envelope
    /// 就會一路出境而不經任何檢查，連 PIPL 硬牆都繞過（硬牆掃的是文字）。
    ///
    /// 修法刻意不是「加一段掃圖的邏輯」——圖沒辦法掃。改成**結構上不可能漏**：
    /// 沒有人明確決定要送，圖就會在這裡被拿掉。忘記傳這個參數的後果是「少了一張圖」，
    /// 不是「多送了一張不該送的圖」。
    public func check(_ envelope: ContextEnvelope,
                      screenshot: ScreenshotEgressPolicy.Decision =
                        .withhold(reason: "沒有提供截圖出境決定")) -> EgressDecision {
        // 1) 收集所有會出境的文字欄位（含劇本每一步）。
        var fields: [(name: String, text: String)] = [
            ("session_summary", envelope.actionScript.sessionSummary),
            ("open_loop", envelope.actionScript.openLoop),
        ]
        for (i, s) in envelope.actionScript.recentSteps.enumerated() {
            fields.append(("step\(i).whatHappened", s.whatHappened))
            fields.append(("step\(i).inferredGoal", s.inferredGoal))
            for (j, art) in s.artifacts.enumerated() { fields.append(("step\(i).artifact\(j)", art)) }
        }
        if let t = envelope.focusedElementText { fields.append(("focused_text", t)) }
        if let c = envelope.clipboardRecent { fields.append(("clipboard", c)) }
        if let a = envelope.attentionSummary { fields.append(("attention_summary", a)) }

        // 2) PIPL 硬牆：任一欄位命中 → 整包拒出（I6）。
        for f in fields where piplDetector(f.text) {
            return .blocked(reason: f.name)
        }

        // 3) 全欄位過 scrubber 遮罩，重建 envelope。
        let scrub: (String) -> String = { scrubber.scrub($0).clean }
        let steps = envelope.actionScript.recentSteps.map { s in
            ActionStep(id: s.id, startedAt: s.startedAt, app: s.app, category: s.category,
                       whatHappened: scrub(s.whatHappened), inferredGoal: scrub(s.inferredGoal),
                       confidence: s.confidence, artifacts: s.artifacts.map(scrub), openLoop: s.openLoop)
        }
        var out = envelope
        out.actionScript = ActionScript(sessionSummary: scrub(envelope.actionScript.sessionSummary),
                                        recentSteps: steps,
                                        openLoop: scrub(envelope.actionScript.openLoop))
        out.focusedElementText = envelope.focusedElementText.map(scrub)
        out.clipboardRecent = envelope.clipboardRecent.map(scrub)
        out.attentionSummary = envelope.attentionSummary.map(scrub)

        // 4) 截圖：只有明確決定要送才留下。
        //    ⚠️ 這裡**不**驗證塗黑真的做過了——像素驗不了。決定裡的矩形是給編碼端的契約，
        //    而編碼端（app 層）在編碼前套用它。這一層能保證的是「沒有決定就沒有圖」。
        if case .withhold = screenshot { out.focusSnapshotJPEGBase64 = nil }
        return .allow(out)
    }
}
