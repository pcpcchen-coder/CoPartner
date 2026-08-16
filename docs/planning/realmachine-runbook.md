# 真機 dogfood runbook — 六個 🔒 里程碑（需要你的 Mac）

> backlog 1–57 的 **CI 可測部分全部完成、三 job 綠**。剩下的都是「只有真硬體能驗」的驗收：
> `24 / 29 / 36 / 42 / 53 / 58`（＋延後的擷取 CPU 優化 `23.5`）。
> 我（開發代理）跑在 Linux 容器、無 Mac / GPU / 螢幕 / 權限 / Apple Intelligence / 雲端金鑰，**無法代跑**。
> CI 只保證「編譯 + 純邏輯測試」；行為、效能、真 API 相容性要你在 Mac 上驗。
>
> **每個里程碑分三塊**：①**我要先補的真機膠水**（動手前你先叫我做，這些是 🔒 by nature、CI 驗不到）→
> ②**你在 Mac 上跑**的步驟 → ③**回報**（你貼結果，我據此修 + 標 ✅）。
> 一次做一個里程碑即可，順序建議照下面（B→C→D→E→F→G 對應 M1→M6）。
>
> 每次開工前先： `cd <repo> && git pull origin claude/loving-darwin-Ka636 && ./scripts/bootstrap.sh && open apps/CoPartner/CoPartner.xcodeproj`
> （有新檔一定要重跑 bootstrap 讓 xcodegen 重生專案。）

---

## M1 — Step 24：影片區 DYNAMIC + CPU（前置：Step 23.5）

**現況**：Step 18 已驗過擷取整條在真機通（SCStream+Metal+管線）。但目前是**固定 2fps、每幀 hash 整個螢幕所有 tile**，且 DYNAMIC 狀態機（step 19/20，CI 已測）**還沒真正拿來降頻**、UI 也沒顯示 tile 狀態。

**① 我要先補的膠水（Step 23.5，動 24 之前先叫我做）**
- 只 hash SCK `dirtyRects` 命中的 tile（GPU dispatch 子集，非全螢幕）——目前 `SCKFrameProducer` 算全部。
- 移除同步 `waitUntilCompleted`，改 completion handler，不阻塞 sample queue。
- 注意力驅動自適應幀率（`CapturePyramid` 已設計）：idle 0.2–1fps、活動處拉高；DYNAMIC 區降頻跳 OCR。
- 選單顯示目前各狀態 tile 數（cold/warm/hot/dynamic），讓你肉眼看到 DYNAMIC 有觸發。
- **建議配 Instruments（Time Profiler + GPU）抓真熱點再動手，勿再猜**。

**② 你在 Mac 上跑**
1. 開始觀察 → 播一段 **1080p 影片**（YouTube 全螢幕 / QuickTime）。
2. 看選單新增的狀態行：影片區的 tile 應進 **DYNAMIC**（數字 > 0）。
3. 活動監視器搜 `CoPartner`，記 CPU%：**桌面靜置** / **一般操作** / **播 1080p 影片** 三種。

**③ 回報**：三種情況 CPU%（CoPartner 單一程序）＋影片區有沒有標到 DYNAMIC ＋播影片時程式順不順（不卡頓/不燙）。
**驗收標準**：影片區正確標 DYNAMIC；因降頻，播影片 CPU **不超過**一般操作的 baseline（不該因為「動得多」就線性飆高）。

---

## M2 — Step 29：局部 OCR 吞吐 + 辨識品質 — ✅ 已通過（2026-08-15，實測 18%）

> **已完成，保留作為後續里程碑的參考範例。** 實測 18% ≤ 20% 目標；辨識中英混合正確、未混入他 app 文字。
> 過程中修掉三個真機才現形的問題：FOCUS 狂刷（AX value 誤當視窗識別）、OCR 截整螢幕、
> sidecar 缺 `[build-system]` 導致 `uv run copartner-sidecar` spawn 失敗。詳見 backlog step 29 節。
> **環境提醒（對後續里程碑都適用）**：未簽章開發版每次 rebuild 會使 TCC 授權失效 →
> `tccutil reset ScreenCapture com.pcpcchen.copartner.CoPartner` 後重新授權，並**停止再重跑**；
> 根治請在 Signing & Capabilities 指定固定 Team。
> sidecar 啟動：`cd sidecar && uv sync && uv run copartner-sidecar`（或 `uv run uvicorn copartner_sidecar.server:app --host 127.0.0.1 --port 8765`）。

**現況**：OCR ROI 映射（step 25）、AX-text-first 決策（step 26）、sidecar `/ocr` 接線 + 合約 pytest（step 27/28）都 CI 綠。真 `ocrmac`/Vision 辨識、真吞吐沒驗過。

**① 我要先補的膠水**
- `AppCoordinator` 把 dirty tile 的 ROI → 呼叫 sidecar `/ocr`（或 Swift 端 Vision）→ 文字進劇本；目前擷取事件只更新摘要，還沒接 OCR 呼叫。
- 起 sidecar：`cd sidecar && uv run copartner-sidecar`（會 lazy import 真 `ocrmac`；首次需 `uv sync`）。

**② 你在 Mac 上跑**
1. sidecar 起著，開始觀察。
2. 在一個**有中英夾雜文字**的視窗（如網頁/編輯器）操作。
3. 確認劇本行出現 OCR 抓到的文字片段（而非只有 TYPE/FOCUS）。
4. 量：對同一畫面，V2（只 OCR dirty tiles）的 OCR 呼叫量/CPU vs 「整螢幕 OCR」的粗估。

**③ 回報**：辨識出的中/英文對不對、有沒有明顯漏字；OCR 讓 CPU 上升多少；有沒有延遲感。
**驗收標準**：局部 OCR 像素吞吐 **≤ V1 全螢幕的 ~20%**；zh-Hant + en 辨識堪用。

---

## M3 — Step 36：8hr 磁碟 ≤ 400MB + 語意檢索 + 真 vec0

**現況**：reference+delta 重建（31）、L1 熱環（32）、`MemoryStore`+in-memory KNN（33）、re-baseline（34）、熱圖（35）全 CI 綠。但 `SQLiteVecIndex` 目前是**佔位**（`insert` 直接 throw `.notWired`），真像素持久化也沒接。

**① 我要先補的膠水**
- `SQLiteVecIndex` 真接線：`import SQLite3` + `sqlite3_load_extension("vec0")` + `CREATE VIRTUAL TABLE ... USING vec0(embedding float[768])` + KNN 查詢。**先確認 `sqlite-vec` 裝得起來**（`brew install` 或編譯 .dylib），把路徑餵給 loader。
- 真 embedder（先用 `HashingEmbedder` 也能驗管線，語意品質要等 step 38 的 FoundationModels 句向量）。
- reference+delta 真像素落盤（`ReferenceDeltaStore` 的 TileCell.payload 存真壓縮 bytes）。

**② 你在 Mac 上跑**
1. 開著觀察 **連續 8 小時**（正常用電腦即可，讓它背景記）。
2. 看資料目錄大小（我會把路徑印在選單/log）。
3. 跑一次語意檢索（我會加個 debug 入口：輸入「上週改的重連邏輯」類 query → 看撈回的 step）。
4. 抽樣：對某個時間點 `reconstruct()` 出的畫面 vs 當時真截圖比對（我加 debug dump）。

**③ 回報**：8hr 後磁碟佔用 MB；檢索撈回的 step 相不相關；重建畫面有無明顯損壞。
**驗收標準**：8hr 磁碟 **≤ ~400MB**；真 vec0 載入成功、檢索可用；重建**無損**（抽樣一致）。

---

## M4 — Step 42：本地敘事 sub-second + FoundationModels availability

**現況**：規則式 Narrator + fallback 階梯 + L2 摘要 + sidecar `/vlm` 接線都 CI 綠。`FoundationModelsNarrator` 用 `#if canImport(FoundationModels)` 隔離，**CI 根本沒編譯它**——真機（macOS 26 + Apple Intelligence 開啟）才第一次編譯與執行。

**① 我要先補/驗的膠水**
- 這是 canImport 區塊**第一次真編譯**——`LanguageModelSession` / `@Generable` / `prewarm()` / `session.respond(to:generating:)` 的**實際 API 簽章若與我寫的有出入，會在這裡才報錯**。我會在你的 Mac 上（或你貼編譯錯誤給我）逐一對簽章微調。
- `AppCoordinator` 把 L0 劇本行餵給 `NarrationLadder` → 產 L1 ActionStep → 進 L1HotBuffer/MemoryStore（目前 triggerIntervention 暫用 L0 行當摘要，真 L1 取材要接這條）。
- sidecar `/vlm`：`uv sync` 裝 `mlx-vlm`（~5–6GB Qwen2.5-VL-4bit 首次下載）。

**② 你在 Mac 上跑**
1. 「系統設定 → Apple Intelligence」確認已開啟。
2. 觀察一段操作 → 看 L1 敘事是否產出（劇本從「一行行事件」升級成「一句話 step + 推測目標」）。
3. 量單次 L1 rollup 延遲（我加計時 log）。
4. 關掉 Apple Intelligence 再試 → 應自動 fallback 到規則式（不中斷）。

**③ 回報**：canImport 區塊**能不能編譯**（貼任何 red error）；FoundationModels availability 狀態；L1 敘事像不像人話、意圖猜得準不準（主觀抽樣）；單次延遲 ms。
**驗收標準**：本地敘事路徑 **sub-second**（L1 < ~300ms、prewarm 生效）；availability 檢測正確、關閉時 fallback 通。

#### 🔬 第一次真機實測（2026-08-16）與延遲目標的再評估

**過的**：availability 偵測正確（顯示「可用（Apple Intelligence）」）、階梯確實走 `本地 3B`
（不是 fallback）、`MemoryStore` 有寫入、敘事讀起來像人話且推測合理。

**沒過的**：單次延遲 **2659ms**，是 ~300ms 目標的 9 倍。

**根因**：端上 3B 的生成是**逐 token 串行**的，總延遲幾乎與輸出長度成正比。實測那次輸出
約 80+ 個中文字（`whatHappened` + `inferredGoal`）加 6 欄位的 JSON 結構 ≈ 100–150 tokens；
以 3B 在 M 系列約 30–50 tok/s 計，2.5–3.7s 完全吻合。prefill 與 session 建立相比微不足道。

**因此 ~300ms 對「6 欄位結構化 step」這個輸出形狀是達不到的**——300ms 大約只夠 12–15 個
token，塞不下兩段散文欄位加一個陣列。這不是調校問題，是輸出形狀與模型吞吐的算術。

**已做的優化**（待第二次實測）：`@Guide` 加硬性字數上限（20 字 / 15 字）、instructions
要求極度簡潔、rollup 視窗 40 → 20 行。預期落在 ~800–1200ms。

**⚠️ 待使用者裁決**：`~300ms` 是規劃期自訂的數字，並非外部約束。建議改為
**「L1 < ~1.5s，且不阻塞 L0 即時劇本」**——真正的 UX 不變式是即時劇本永遠不卡，
而 rollup 跑在背景 task、`await` 會讓出 MainActor，UI 不會凍結。
若堅持 sub-second，替代路線是把 step 砍成 3 欄位（category / whatHappened / openLoop），
`inferredGoal` 與 `artifacts` 移到 L2 批次階段再補。

---

## M5 — Step 53：接手全鏈（最關鍵的安全驗收）

**現況**：整條交棒鏈的**邏輯**都 CI 綠——打包/出境閘門/請求組裝/座標換算/解析/HUD 狀態機/ApprovalToken/風險分級/危險指令偵測/沙箱政策/速率迴圈/undo。但**真執行端全是注入點、預設沒接**（`performer=nil` → `.notWired`；`transport=nil` → handoff 收「尚未接線」）。

**① 我要先補的膠水（這個里程碑膠水最多，動手前逐項確認）**
- ⚠️ **先用 `/claude-api` 對齊 live computer-use 契約**：`HandoffRequestBuilder` 的預設 `betaHeader="computer-use-2025-11-24"` / `toolType="computer_20251124"` 是開發時 docs 連不上、暫定的值，**很可能過時**——開工第一件事就是查當下正確的 beta header / tool 版本 / 請求 schema / 支援模型，改預設（一行）。
- 真 `HandoffTransport`：LiteLLM gateway（`cd infra/litellm && litellm --config config.yaml`，設 `ANTHROPIC_API_KEY`）→ Claude computer-use → SSE tool_use 正規化成 `[String:String]` 餵 `ProposedActionParser`。
- 真 `ActionExecutor.performer`：XPC service（`_ambient` 低權 user）+ code-signing requirement 驗證（只收主 app）+ `sandbox-exec` sbpl 套用 + `posix_spawn` argv 直呼（無 shell）；⚠️ **先驗 `sandbox-exec` 在你的 macOS 版本仍可用**，否則走威脅模型 §6 備援。
- 接手 HUD 的 SwiftUI 常駐浮層（顯示提議動作原文 + 風險原因 + Approve/Skip/Stop）。

**② 你在 Mac 上跑**（對照 `docs/design/sandbox-threat-model.md` I1–I10 逐項勾）
1. 做一半某件事（留個 open loop，如寫一半的函式）→ 按 **⌃⌥⌘Space**。
2. HUD 應顯示 Claude 推測的任務 + 下一步 + 信心；**不該貼一堆說明文字**，而是接續你的 open loop。
3. 高風險動作（改檔/刪除/對外送出）→ HUD **強制確認**；危險指令（`rm -rf`/`sudo`…）→ 被攔、顯示原因。
4. 接手到一半按 **⌃⌥⌘.** → 串流立刻斷、HUD 進 aborted、後續 token 全失效（世代作廢）。
5. 故意從別的程序打 XPC → 應被 code-signing 擋。
6. sbpl：讓沙箱內動作試連網/寫工作目錄外 → 應被 deny。
7. LiteLLM `max_budget: 5` → 跑到超額一次，確認熔斷。

**③ 回報**：I1–I10 每條過沒過；computer-use 契約對齊後有沒有相容性問題；接手體驗（Claude 有沒有正確續寫）；kill-switch 是不是真的全鏈斷。
**驗收標準**：熱鍵後 Claude 正確接續 open loop；高風險強制確認、危險指令攔下；⌃⌥⌘. 全鏈中止；XPC 擋外來；sbpl 實際 deny；budget 熔斷。

---

## M6 — Step 58：PIPL 最終隱私審查

**現況**：tile 遮罩（55）、黑名單（56）、熱圖隱私（57）邏輯全 CI 綠。真 `kAXSecureTextField` 偵測、URL/OCR 啟發式、真 `SCContentFilter(display:including:)` 黑名單膠水沒接。

**① 我要先補的膠水**
- 真敏感 region 偵測 → 餵 `SensitiveTileMask.update`：AX 查 `kAXSecureTextField`（密碼欄）、前景 URL/視窗標題啟發式、OCR 命中 PII 正則（卡號/身分證/API key）。
- `AppCoordinator.startCapture` 改用 `CaptureBlacklist.includeList` → `SCContentFilter(display:including:)`（白名單實作，`nil` 時該幀不開 stream）。

**② 你在 Mac 上跑**
1. 到任一**密碼欄**輸入 → 確認：劇本行是 `[在密碼欄輸入]`、該區 tile **不 OCR/不持久化/不進熱圖**（三處皆無明文）。
2. 開**黑名單 app**（如 1Password）→ 確認擷取 **0 frame** 進來（摘要不動、資料無該 app 畫面）。
3. 確認 **CoPartner 自己**（選單/HUD）不被自錄（無錄製迴圈）。
4. 熱圖 summary 不指向剛才的密碼欄區域。
5. 對照 `sandbox-threat-model.md` I6 + `v1_full-design.md` §G 資料分類矩陣（絕不出本機 / 遮罩後可上雲 / 可上雲）跑一輪全案稽核。

**③ 回報**：密碼欄是否 100% 無明文外洩（三處）；黑名單 app 是否真 0 frame；自身 app 有無被錄；有無任何敏感畫面漏遮。
**驗收標準**：密碼欄/銀行頁 100% 遮；黑名單 app 0 frame；自身 app 不自錄；全案隱私稽核通過。

---

## 附：延後的 Step 23.5（擷取 CPU 優化）

不是驗收里程碑，是 Step 24 的前置工程（見上面 M1 ①）。可在做 M1 時一起處理，或你覺得目前 CPU（真機實測 idle 9% / operating 25%，系統整體僅 ~10%）可接受就先擱著。

---

驗完任一里程碑，把該節 **③ 回報** 貼給我，我據此：(a) 修真機發現的問題、(b) 對齊需微調的真 API 簽章、(c) 標記該 step ✅。六個都過 = 全 backlog（58 步）完成。
