# Roadmap（macOS-first，個人 side project 節奏 5–10 hrs/週）

> 完整 milestone 細節見 docs/design/v2_smart-capture-engine.md §J 與 v2.1 §7。

| Milestone | 交付物 | 估時 | 驗收（量化） |
|---|---|---|---|
| **M0** 擷取引擎原型 | SCK + dirtyRects + Metal tile dHash + 滑鼠 attention；純擷取無 AI | 3–4 週 | M4 真機量 CPU%/漏抓率/延遲；產出 V1 vs V2 對照數字 |
| **M1** 冷熱狀態機 + DYNAMIC | tile 狀態機 + 影片降頻/跳 OCR + foveation 排程 | 2–3 週 | 播 1080p 影片 CPU 不超 baseline；影片正確標 DYNAMIC |
| **M2** 局部 OCR + AX 文字 | Vision regionOfInterest OCR + AX 文字優先 | 2 週 | OCR 像素吞吐 ≤ V1 的 20% |
| **M2.5** L0 EventLog | deterministic 模板劇本，無模型 | 1–2 週 | 劇本完整重現一段操作（時間機器） |
| **M3** 記憶系統 | reference+delta 持久化 + sqlite-vec + 熱圖 | 2–3 週 | 8hr 磁碟 ≤ ~400MB；語意檢索可用 |
| **M4** 本地推理 + L1/L2 敘事 | Qwen2.5-VL MLX + FoundationModels ActionStep | 2–3 週 | 本地路徑 sub-second；L1 意圖準確率達標 |
| **M5** 雲端 + 動作 + 交棒 | LiteLLM + Claude CU + ContextEnvelope + takeover + ActionExecutor | 3–4 週 | 不貼說明，熱鍵後 Claude 正確接續 open loop |
| **M6** 隱私 + 黑名單 | tile 遮罩 + SCContentFilter 黑名單 + 熱圖隱私 | 2 週 | 密碼欄/銀行頁 100% 被遮；黑名單 app 0 frame |

**起步建議**：先做 M0 的 Tier 2 簡化版（滑鼠/焦點 attention region + 周邊定頻 + SCK idle dedup），
用真機數字決定是否投入完整 tile 狀態機。
