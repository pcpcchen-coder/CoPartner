# CoPartner 開發執行計畫：模型分工策略、實作規劃、時程與費用評估

> 目的：回答「哪個階段用 Fable 5 / Opus 4.8 / Sonnet 5」「完整實作怎麼排」「大概多久」「訂閱怎麼選最划算」。
> 範圍：M0–M6（見 `docs/roadmap.md`、`docs/design/v2_smart-capture-engine.md §J`）。此文件是**開發流程**規劃，不重複產品架構決策（那些留在 ADR / design 文件）。
> 撰寫日期：2026-07-02。訂閱方案與用量上限會隨時間調整，正式決定前請以 [claude.com/pricing](https://claude.com/pricing) 現況為準（見 §5 附註）。

---

## 1. 核心原則：分層模型策略

CoPartner 本身的 ADR-0007（本地優先分層推理 + 雲端升級）給了一個現成的類比：**小範圍、例行的工作留在便宜的層級，只有「大變動 / 高不確定性 / 犯錯代價高」才升級到最貴的層級**。開發這個專案時，你（開發者）與 Claude Code 的協作也適用同一個原則，只是把「本地模型 vs 雲端」換成「Sonnet 5 vs Opus 4.8 vs Fable 5」：

```
Sonnet 5  →  Opus 4.8  →  Fable 5
(日常主力)   (里程碑起手／除錯／審查)   (無先例的高難問題／Opus 卡關兩次以上)
```

**預設模型：Sonnet 5**，理由：
- Claude Sonnet 5 在 coding/agentic 任務上已達到「先前 Opus 等級」的品質，同時價格只有 Opus 的 ~40–60%（含到 2026-08-31 為止的入門價 $2/$10 每 MTok）。
- 這個專案是 **solo side project，5–10 hrs/週**，時間與預算都有限——多數工作是「照 design doc 寫程式、修 CI、寫測試、補文件」這類例行工作，不需要每次都動用最貴的模型。

**升級到 Opus 4.8** 的時機：新里程碑起手（架構草圖一次要定對）、除錯疑難雜症、合併前的 code review、安全/隱私關鍵路徑。

**升級到 Fable 5** 的時機：**很少但關鍵**——只用在整個專案裡「無參考實作、長時間高模糊度」的核心難題（見 §3 M0、M5），或 Opus 4.8 在同一個問題上卡關兩次以上時的最後手段。Fable 5 定價是 Opus 的 2 倍（$10/$50 vs $5/$25），且單次請求可能跑好幾分鐘，不適合當日常主力。

操作上非常簡單——直接在 Claude Code 打 `/model claude-sonnet-5`、`/model claude-opus-4-8`、`/model claude-fable-5` 切換，或用 `/fast`（Opus 4.8 限定，加速但加價，本專案不建議常態使用）。

---

## 2. 模型速查表（2026-06-24 快取價格）

| 模型 | Model ID | Context | Input / Output（每 1M tokens）| 定位 |
|---|---|---|---|---|
| **Claude Sonnet 5** | `claude-sonnet-5` | 1M | $3 / $15（**入門價 $2/$10，至 2026-08-31**）| 日常主力：coding/agentic 已近 Opus 品質，`effort` 支援到 `xhigh` |
| **Claude Opus 4.8** | `claude-opus-4-8` | 1M | $5 / $25 | 最強 Opus 級：長程自主任務、知識工作、記憶最佳；起手/除錯/審查用 |
| **Claude Fable 5** | `claude-fable-5` | 1M | $10 / $50 | 目前最強公開模型：最難推理與長程 agentic 工作；單次請求可能數分鐘 |
| Claude Haiku 4.5 | `claude-haiku-4-5` | 200K | $1 / $5 | 機械式雜務（改名、格式化、簡單腳本），本專案非必要但可選 |

> Sonnet 5 入門價只到 **2026-08-31**（距今約 2 個月，落在 M0/M1 期間）——如果你會用**直接 API 計費**（非訂閱）補足尖峰產能，把握這段時間跑 Sonnet 5 重度工作最划算。訂閱制（Pro/Max）月費固定，不受此影響。

---

## 3. 任務類型 × 模型 決策矩陣

不論在哪個里程碑，用這張表快速判斷該切哪個模型：

| 任務類型 | 建議模型 | 理由 |
|---|---|---|
| 照設計文件寫程式、CRUD、glue code、Package.swift 這類鷹架 | **Sonnet 5** | 品質夠、便宜、快，佔專案工作量大宗 |
| 新里程碑起手／架構草圖 | **Opus 4.8** | 骨架一次定對，後面省掉重構成本 |
| CI 修復（錯誤訊息明確、範圍小）| **Sonnet 5** | 如本次 CGPoint import 修復——不需要最強模型 |
| 除錯疑難雜症（原因不明、多次嘗試失敗）| **Opus 4.8**，卡關 2 次以上升 **Fable 5** | 需要深度推理與長時間單一 session 排查 |
| Merge 前 code review | **Opus 4.8** | recall 較高，較不會漏掉真的 bug |
| 文件撰寫（ADR、README、commit message）| **Sonnet 5**（機械式的可用 Haiku 4.5）| 對話式寫作不需要最強推理 |
| 安全／隱私關鍵路徑（M5 sandbox、M6 遮罩邏輯）| 架構定案 **Fable 5**／日常迭代 **Opus 4.8** | 犯錯代價高（沙箱逃逸、PII 洩漏） |
| 全新技術棧、無參考實作的核心演算法（M0 dirty-region + Metal hash）| **Fable 5** 起手／卡關，**Opus 4.8** 日常迭代 | 長時間、高模糊度、無先例可循 |
| 機械式重構、批次改名、格式化（尤其用 subagent 批次跑）| **Sonnet 5** 或 **Haiku 4.5** | 低推理需求，subagent 用便宜模型可控成本 |

**額外槓桿——`effort` 參數**：同一模型內也能透過 `output_config.effort`（`low`/`medium`/`high`/`xhigh`/`max`）控制思考深度與花費。Claude Code 內部通常已依任務自動調整；若你手動下 API 呼叫或寫 subagent workflow，可對「例行工作」用 `medium`、「難題」用 `high`/`xhigh`，比整個換模型更細緻地控成本。

---

## 4. 里程碑執行規劃（M0–M6）

延續 `docs/roadmap.md` 與 `docs/design/v2_smart-capture-engine.md §J` 的交付物與驗收標準，這裡補上**建議模型與風險理由**：

| 里程碑 | 核心任務 | 估時 | 建議模型 | 為什麼 | 驗收 |
|---|---|---|---|---|---|
| **M0** 擷取引擎原型 | SCK dirtyRects + Metal tile dHash shader + CGEventTap 滑鼠 attention | 3–4 週 | **Fable 5**（起手/卡關）+ **Opus 4.8**（日常）| Design doc 明講「無現成 macOS foveated/tile dirty-region 擷取開源專案」；已知陷阱：SCK status 常回 idle、dirtyRects 可能空、Sequoia 15.6.1 contentRect X=48 bug——這是全專案模糊度最高的部分 | 真機 CPU%/漏抓率/延遲；V1 vs V2 對照數字 |
| **M1** 冷熱狀態機 + DYNAMIC | tile 狀態機、影片降頻跳 OCR、foveation 排程 | 2–3 週 | **Sonnet 5** 主力 + **Opus 4.8** 審查 DYNAMIC 判定邏輯 | 狀態表已在 design doc §B.6 定義清楚，屬「照規格實作」；但誤判閾值（video vs 真變動）值得 Opus 審一次 | 播 1080p 影片 CPU 不超 baseline；正確標 DYNAMIC |
| **M2** 局部 OCR + AX 文字 | Vision `regionOfInterest` OCR + AX 文字優先 | 2 週 | **Sonnet 5** | 用既有 Apple API（Vision/Accessibility），文件齊全，新穎度低 | OCR 像素吞吐 ≤ V1 的 20% |
| **M2.5** L0 EventLog | deterministic 模板劇本，無 ML 模型 | 1–2 週 | **Sonnet 5**（甚至可試 Haiku 4.5 跑機械式模板生成）| 全專案最機械的一塊 | 劇本完整重現一段操作 |
| **M3** 記憶系統 | reference+delta 持久化、sqlite-vec、注意力熱圖 | 2–3 週 | **Sonnet 5** 實作 + **Opus 4.8** 審查 delta 重建正確性 | delta 重建錯了會靜默資料損毀，值得多一道高 recall 審查 | 8hr 磁碟 ≤ ~400MB；語意檢索可用 |
| **M4** 本地推理 | Qwen2.5-VL MLX 整合 + FoundationModels 3B 意圖分類 | 2–3 週 | **Opus 4.8** 主力 | 新整合面（MLX、FoundationModels availability check + fallback）容易踩到框架特有的坑，Opus 的長程推理較能一次抓對 | 本地路徑 sub-second；L1 意圖準確率達標 |
| **M5** 雲端 + 動作 + 交棒 | LiteLLM Gateway、Claude computer-use 整合、ContextEnvelope、sandboxed ActionExecutor、風險分級確認 | 3–4 週 | **Fable 5**（sandbox 風險分級架構定案 + computer-use 協定整合）+ **Opus 4.8**（日常迭代）| 全專案第二高風險：AI 發出指令、sandbox 執行——架構一旦設計錯就是真的安全漏洞；computer-use 協定本身也有座標縮放/beta header 等細節要一次搞對 | 熱鍵後 Claude 正確接續 open loop；高風險動作強制確認 |
| **M6** 隱私 + 黑名單 | tile 遮罩（PII regex）、SCContentFilter 黑名單、熱圖隱私 | 2 週 | **Opus 4.8** 主力（遮罩正確性審查）+ **Sonnet 5**（SCContentFilter 接線）| 遮罩漏抓 = PII 外洩，但範圍比 M5 小、design doc §G 已把啟發式定義清楚 | 密碼欄/銀行頁 100% 被遮；黑名單 app 0 frame |

**粗估模型使用比例（依工作量，非天數）**：Sonnet 5 ~75–80% ・ Opus 4.8 ~15–20% ・ Fable 5 ~3–5%（集中在 M0 起手 + M5 架構定案）。

---

## 5. 開發時程估算

延續 roadmap 的週數估計（solo，5–10 hrs/週），以 **2026-07-02（今天）** 為起點，累計三種情境：

| 里程碑 | 估時 | 樂觀累計完成 | 保守累計完成 |
|---|---|---|---|
| M0 | 3–4 週 | ~2026-07-23 | ~2026-07-30 |
| M1 | 2–3 週 | ~2026-08-06 | ~2026-08-20 |
| M2 | 2 週 | ~2026-08-20 | ~2026-09-03 |
| M2.5 | 1–2 週 | ~2026-08-27 | ~2026-09-17 |
| M3 | 2–3 週 | ~2026-09-10 | ~2026-10-08 |
| M4 | 2–3 週 | ~2026-09-24 | ~2026-10-29 |
| M5 | 3–4 週 | ~2026-10-15 | ~2026-11-26 |
| M6 | 2 週 | **~2026-10-29** | **~2026-12-10** |

- **樂觀情境**：17 週（~3.9 個月），完成於 ~2026 年 10 月底。
- **保守情境**：23 週（~5.3 個月），完成於 ~2026 年 12 月初。
- **實務建議抓中位數再加緩衝**：side project 常因現實生活中斷而超出估計，建議以 **~20–24 週（~2026 年 11 月中～12 月中）** 當作對外承諾/自我期待的基準，年底前完成是合理目標。

---

## 6. 費用與訂閱方案評估

### 6.1 為什麼訂閱制通常比直接 API 計費划算（此專案的使用型態）

這個專案是「人在迴圈中、長期互動式 coding」——與 API 直接計費（依 token 計價、無上限）相比，訂閱制把用量收斂在固定月費內，對「每週穩定投入數小時、混用 Sonnet/Opus/偶爾 Fable」的用法通常更省錢也更好預算。API 直接計費更適合：(a) 大量平行/夜間自動化（例如用 Workflow 批次跑多個 subagent），(b) 想用 **Batch API（5 折）** 處理非即時任務。這兩種都可以當作訂閱的**補充**，而非取代。

### 6.2 訂閱方案比較（solo 開發者視角）

| 方案 | 月費 | 內容 | 是否適合本專案 |
|---|---|---|---|
| Free | $0 | 極少量用量 | ❌ 不夠跑 agentic coding |
| **Pro** | $20/mo（年繳 ~$17/mo）| Claude Code 含在內，Sonnet + Opus 共用一個額度池，5 小時滾動窗 + 週上限 | ⚠️ 僅適合「幾乎全程用 Sonnet 5、Opus 極少用」或每週真的只有 ~5hr 且互動不密集 |
| **Max 5x** | $100/mo | Pro 的 5 倍額度；Sonnet 與 Opus 分開計算的週額度 | ✅ **建議預設** |
| **Max 20x** | $200/mo | Pro 的 20 倍額度 | ✅ 建議只在 M0、M5 尖峰週短期升級 |
| Team Standard | $20–25/席，最少 5 席 | **不含 Claude Code** | ❌ solo 用不到，且沒有 Code |
| Team Premium | $100–125/席，最少 5 席 | 含 Claude Code，但最低 5 席 ⇒ 至少 $500/mo | ❌ 比 Max 20x 貴 2.5 倍還買不到對等的個人產能 |
| Enterprise | 客製報價 | 治理/合規/資料落地需求 | ❌ 不是這個場景的問題 |

> ⚠️ 上表金額與額度結構來自公開資訊彙整（見文末來源），**Anthropic 會不定期調整方案內容與確切額度（例如 2026-05-06 曾把 Pro/Max 的 5 小時額度加倍）**。實際決定訂閱前，請直接到 [claude.com/pricing](https://claude.com/pricing) 核對當下數字——本文件嘗試直接抓取該頁時被伺服器擋下（403），故以搜尋彙整結果為準，可信度略低於一手頁面。

### 6.3 推薦方案與預估總成本

**預設：Max 5x（$100/mo）**，搭配：

1. 日常模型設 **Sonnet 5**（`/model claude-sonnet-5`，本次 session 已切換）。
2. 每個里程碑起手、除錯卡關、merge 前審查時手動切 **Opus 4.8**（`/model claude-opus-4-8`）。
3. Fable 5 只在 M0 起手（Metal shader / dirty-region 核心演算法）與 M5 架構定案（sandbox 風險分級）時短暫使用，或 Opus 卡關兩次以上時當最後手段。
4. **M0、M5 這兩個尖峰月**（各約 3–4 週、Opus/Fable 用量最高）：當月臨時升級到 **Max 20x（$200/mo）**，用完當月降回 Max 5x——訂閱可逐月調整，不需要整個專案期間都買最高階。
5. 用 Claude Code 的 `/cost` 指令或 Console 用量儀表板，在頭 2–3 週校準實際用量——如果發現 Sonnet 5 幾乎打滿所有需求、Opus 很少動用，Pro（$20/mo）可能就夠，直接降階省錢。

**預估總成本（以 ~4.5–5 個月專案期估算，僅供參考）**：

| 策略 | 估算 | 總成本 |
|---|---|---|
| 全程 Pro | 4.5 × $20 | ~$90 |
| 全程 Max 5x | 4.5 × $100 | ~$450 |
| **混合（推薦）**：Max 5x 多數月份 + Max 20x 於 M0/M5 尖峰（合計 ~2 個月）| 2.5×$100 + 2×$200 | **~$650** |
| 全程 Max 20x | 4.5 × $200 | ~$900 |

混合策略比「全程買最高階」省 ~28%，又比「全程 Pro」在 M0/M5 這種高難度階段有更充裕的 Opus/Fable 額度可用，不會卡在額度不足而被迫用較弱模型硬撐風險最高的兩個里程碑。

### 6.4 若想搭配直接 API（選用）

- 大規模平行/自動化任務（例如用 `Workflow` 對多檔案批次重構或審查）：走 API 計費 + **Batch API 5 折**，比塞進互動式訂閱額度更划算，也不會排擠日常互動用量。
- 若選擇直接 API：**2026-08-31 前**用 Sonnet 5 有入門價（$2/$10 vs 標準 $3/$15），正好覆蓋 M0～M1 前段，值得把這段時間的 Sonnet 5 重度工作排進去。
- 直接 API 用量務必先用 `messages.count_tokens` 或實際跑 1–2 週抓真實數字校準，不要憑感覺估——本文件不推算「每小時多少 token」這種容易失準的假設值。

---

## 7. 風險與待驗證假設

- 週數估計（M0–M6）沿用既有 roadmap，未重新拆解；若前幾個里程碑實測進度落後，建議在 M1 結束時重新校準後續估計，而非硬套本文件的日期。
- 訂閱方案的**確切額度數字**（例如 Max 5x/20x 各自的週 Opus/Sonnet 小時數）本文件未能一手驗證，只列出資訊來源作為方向；正式訂閱前請自行核對 claude.com/pricing 當下條款。
- Fable 5 在 Claude Code 訂閱制下的可用性（是否所有付費層都能叫、有無額外限制）未能一手驗證——若 `/model claude-fable-5` 在你的方案下不可用或用量消耗異常快，改以 Opus 4.8 頂替 M0/M5 的最難問題即可，不影響整體策略。
- 本文件所有金額為**當前（2026-07-02）牌價**，Anthropic 過去有過中途調整方案內容的紀錄（如 2026-05-06 的額度加倍），長期專案中途可能需要重新評估。

---

## 來源

- Claude API 模型與定價：Anthropic `claude-api` skill 快取資料（快取日期 2026-06-24，取自本 session）。
- Claude Code 訂閱方案（Pro/Max/Team/Enterprise）：[claude.com/pricing](https://claude.com/pricing)、[Claude Help Center — What is the Max plan?](https://support.claude.com/en/articles/11049741-what-is-the-max-plan)、[Claude Help Center — Models, usage, and limits in Claude Code](https://support.claude.com/en/articles/14552983-models-usage-and-limits-in-claude-code)、[Claude Help Center — How do usage and length limits work?](https://support.claude.com/en/articles/11647753-how-do-usage-and-length-limits-work)（透過 WebSearch 彙整，非一手頁面抓取，見 §6.2 附註）。
- 里程碑與估時：`docs/roadmap.md`、`docs/design/v2_smart-capture-engine.md §J`（本專案既有文件）。
