# Roadmap（macOS-first，個人 side project 節奏 5–10 hrs/週）

> 完整 milestone 細節見 docs/design/v2_smart-capture-engine.md §J 與 v2.1 §7。

> ## ⚠️ 範圍重畫（2026-09-05）
>
> **CoPartner 不再自己執行 UI 動作，也不送截圖出境。** 產品是**使用者操作習慣的萃取**——
> 產出人類可讀、廠商中立的文字，交給任何有執行能力的代理（Claude computer-use /
> GPT-6 Astra）使用。理由與後果見 [`adr/0008-habit-extraction-scope.md`](adr/0008-habit-extraction-scope.md)，
> 做法見 [`design/v3_habit-extraction.md`](design/v3_habit-extraction.md)。
>
> **下表的 M5「動作 + 交棒」與 M6「密碼欄 100% 被遮」已失效**，保留供歷史對照。
> 新的驗收是「留一手預測測試」的**差值**（有習慣萃取 vs 沒有），全程本機可跑。

> **狀態（2026-08-19）**：M0–M4 與 M5 的大半已在真機驗過。逐 step 進度以
> [`implementation-backlog.md`](planning/implementation-backlog.md) 為準，本表只講「里程碑層級」。

| Milestone | 狀態 | 交付物 | 估時 | 驗收（量化） |
|---|---|---|---|---|
| **M0** 擷取引擎原型 | ✅ | SCK + dirtyRects + Metal tile dHash + 滑鼠 attention；純擷取無 AI | 3–4 週 | M4 真機量 CPU%/漏抓率/延遲；產出 V1 vs V2 對照數字 |
| **M1** 冷熱狀態機 + DYNAMIC | 🔒 | tile 狀態機 + 影片降頻/跳 OCR + foveation 排程 | 2–3 週 | 播 1080p 影片 CPU 不超 baseline；影片正確標 DYNAMIC |
| **M2** 局部 OCR + AX 文字 | ✅ 吞吐 18% | Vision regionOfInterest OCR + AX 文字優先 | 2 週 | OCR 像素吞吐 ≤ V1 的 20% |
| **M2.5** L0 EventLog | ✅ | deterministic 模板劇本，無模型 | 1–2 週 | 劇本完整重現一段操作（時間機器） |
| **M3** 記憶系統 | 🔒 vec0 待接 | reference+delta 持久化 + sqlite-vec + 熱圖 | 2–3 週 | 8hr 磁碟 ≤ ~400MB；語意檢索可用 |
| **M4** 本地推理 + L1/L2 敘事 | ✅ 1373–2388ms | Qwen2.5-VL MLX + FoundationModels ActionStep | 2–3 週 | 本地路徑 sub-second；L1 意圖準確率達標 |
| **M5** 雲端 + 動作 + 交棒 | 🚧 剩執行端 | LiteLLM + Claude CU + ContextEnvelope + takeover + ActionExecutor | 3–4 週 | 不貼說明，熱鍵後 Claude 正確接續 open loop |
| **M6** 隱私 + 黑名單 | 🔒 | tile 遮罩 + SCContentFilter 黑名單 + 熱圖隱私 | 2 週 | 密碼欄/銀行頁 100% 被遮；黑名單 app 0 frame |

⚠️ **M4 的驗收標準已修訂**：原寫「本地路徑 sub-second」，實測不可能——端上 3B 逐 token
串行生成，延遲與輸出長度成正比，300ms 只夠 12–15 個 token，塞不下結構化 step 的欄位。
**這是輸出形狀與模型吞吐的算術，不是調校問題。** 已改為 ~2.5s 並維持資訊量。

**執行順序（見 `docs/planning/implementation-backlog.md`）**：採「可跑骨架優先」——先把 L0 操作劇本
（只需 Input Monitoring + Accessibility，不需 Screen Recording/Metal）接進既有 menu bar app，
幾週內產出可 dogfood 的「操作時間機器」，再把螢幕擷取（SCStream/Metal）疊上會跑的東西。
逐步待辦已展開成 58 個可獨立交付的 step。

**語音（全日轉錄摘要 + 語音交棒）**：README 願景，本輪 M0–M6 不做，延後至 V3（詳見 backlog 文末）。
