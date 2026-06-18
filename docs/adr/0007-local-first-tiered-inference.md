# 7. 本地優先的分層推理階梯與雲端升級（local-first tiered inference & cloud escalation）

- 狀態：已接受
- 脈絡：ADR-0005 定了「本地負責持續觀察 / 意圖 / PII、雲端負責複雜推理與動作規劃」的分工與隱私邊界，
  但沒定「何時」從本地升級到雲端。若每次畫面變動都送雲端，token 成本與延遲都不可行；
  反之全留本地又吃不下需要跨視窗、多步規劃的大任務。需要一條明確的升級策略。
- 決定：採「本地優先的分層推理階梯」，依變動規模逐級升級，只有大變動才出雲端：
  - **階梯**（便宜 → 貴）：`localOCR`（dirty-tile 文字，§B.8）→ `localIntent`（FoundationModels 3B 意圖 / 路由，§D）
    → `localVLM`（Qwen2.5-VL 焦點拼接圖視覺語意，§D）→ `cloud`（Claude computer-use，§E）。
  - **小範圍辨識留本地**：dHash 聚合的變動面積小（§B.2）、注意力低、本地信心足 → 跑最省的本地階。
  - **大變動才升級雲端**，任一成立即升 `cloud`：
    ① 變動面積 ≥ 門檻（大面積改版 / 換頁）；② 本地模型信心 < 門檻（看不懂）；
    ③ 跨視窗 / 多步規劃任務（單張焦點圖不足以決策）。
  - **隱私閘門最高優先**：含上海團隊個資 / 敏感 tile 一律封頂在本地（最多 `localVLM`），即使變動再大也永不 `cloud`（ADR-0005 / §G）。
  - **防 thrash / 控成本**：雲端升級設冷卻窗（預設 ~4s），冷卻內的連續大變動改用最強本地階（`localVLM`）頂著（類比 ADR-0006 連點 coalesce）。
- 後果：多數時間（小範圍變動）零雲端成本；雲端只在真正需要時介入，token / 延遲可控且可預算熔斷（ADR-0005）。
  與注意力能量（ADR-0006）、冷熱狀態機（§B.6）、dHash 變動量（§B.2）共用同一組訊號。
  門檻為保守起點，須於 M5 真機以「誤升級率 / 漏升級率 / 平均延遲 / 每日 token」調校。
- 實作：訊號型別 `RoutingSignal` 與 `InferenceTier` 於 packages/CoPartnerKit/Sources/CoPartnerCore/Models.swift；
  升級策略 `EscalationPolicy`（CloudRouter 持有並 `decide`）於 .../Sources/CloudRouter/CloudRouter.swift；
  測試見 Tests/CoPartnerKitTests/EscalationPolicyTests.swift；設計細節見 docs/design/v2_smart-capture-engine.md §E.1。
