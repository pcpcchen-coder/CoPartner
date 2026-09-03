# 真機 dogfood runbook — 六個 🔒 里程碑（需要你的 Mac）

> backlog 1–57 的 **CI 可測部分全部完成、三 job 綠**。剩下的都是「只有真硬體能驗」的驗收：
> `24 / 29 / 36 / 42 / 53 / 58`（＋延後的擷取 CPU 優化 `23.5`）。
>
> **戰績（2026-09-02）**：`29` ✅ 通過（吞吐 18%）、`42` ✅ 通過（1373–2388ms）、
> `53` 🔄 進行中（53.1／53.2／53.3／53.7 已真機通過；53.5 開關已翻開、第一次真執行的回報待補；53.6-C 待翻開）；
> `24 / 36 / 58` ⬜ 待做。視覺化全景見 [`docs/project-mindmap.md`](../project-mindmap.md)。
> 我（開發代理）跑在 Linux 容器、無 Mac / GPU / 螢幕 / 權限 / Apple Intelligence / 雲端金鑰，**無法代跑**。
> CI 只保證「編譯 + 純邏輯測試」；行為、效能、真 API 相容性要你在 Mac 上驗。
>
> **每個里程碑分三塊**：①**我要先補的真機膠水**（動手前你先叫我做，這些是 🔒 by nature、CI 驗不到）→
> ②**你在 Mac 上跑**的步驟 → ③**回報**（你貼結果，我據此修 + 標 ✅）。
> 一次做一個里程碑即可，順序建議照下面（B→C→D→E→F→G 對應 M1→M6）。
>
> 每次開工前先： `cd <repo> && git pull origin main && ./scripts/bootstrap.sh && open apps/CoPartner/CoPartner.xcodeproj`
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

## M4 — Step 42：本地敘事 + FoundationModels availability ✅ **真機通過（2026-08-16）**

> **驗收結果**
>
> | 項目 | 結果 |
> |---|---|
> | canImport 區塊真編譯（7 項簽章）| ✅ 一次全過、零紅字 |
> | L1 敘事產出（事件 → 一句話 step + 推測目標）| ✅ 品質合理 |
> | availability 偵測 | ✅ 正確 |
> | 走本地 3B（非 fallback）| ✅ |
> | `MemoryStore` 寫入 | ✅ 累加正常 |
> | **關閉 Apple Intelligence → fallback 規則式** | ✅ **標籤確實從「本地 3B」變「規則式」，不中斷** |
> | L1 延遲 | ✅ 1373–2388ms，符合修訂後的 ~2.5s 標準 |
> | 真 `/vlm`（mlx-vlm Qwen2.5-VL）| 🔒 **延後**——需 sidecar + ~5–6GB 模型下載，且日常使用不依賴它 |
>
> 未做的只有 `/vlm`，它不阻擋 M4 的核心價值（本地敘事鏈路），列入後續。

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
**驗收標準**（2026-08-16 依實測修訂，原為 ~300ms，見下方分析）：
L1 rollup **< ~2.5s 且不阻塞 L0 即時劇本**；prewarm 生效；availability 檢測正確、關閉時 fallback 通。

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

**第二 / 三次實測**：1373ms → 2388ms。優化有效（2659 → 1373）但**不穩定**——
關鍵發現：**`@Guide` 的字數上限模型只當參考、不嚴格遵守**。2388ms 那次輸出約 35 字，
遠超設定的 20 字上限。延遲與輸出長度成正比這點被反覆印證，但光靠 prompt 壓不穩定。

**✅ 已裁決（使用者，2026-08-16）**：驗收標準放寬到 **~2.5s，維持 6 欄位資訊量**。
理由：真正的 UX 不變式是 L0 即時劇本永不卡，而 rollup 跑在背景 task、`await` 會讓出
MainActor，UI 不凍結（真機截圖印證劇本持續即時更新）。`inferredGoal`（推測目標）
正是 L1 的價值所在，不值得為了帳面數字砍掉。

被否決的替代路線（留作記錄）：砍成 3 欄位（category / whatHappened / openLoop）、
把 `inferredGoal` 與 `artifacts` 移到 L2 批次階段，可望壓到 500–800ms，
代價是選單上「↳ 推測目標」即時消失。

---

## M5 — Step 53：接手全鏈（最關鍵的安全驗收）

> **本節於 2026-08-19 依真機結果重寫。** 原本的內容假設「執行端只是接線」，
> 實際做下去才發現它根本還不存在，於是 step 53 展開成 53.1–53.6（見 backlog）。
> 原文裡幾個後來被推翻的假設也一併更正——留著錯的指示比沒有指示更糟。

### 已完成的（不必重驗，除非改到相關程式碼）

| 子步 | 驗收方式 | 結果 |
|---|---|---|
| 53.1 XPC 骨架 | 選單「XPC 自檢」 | ✅ service pid ≠ app pid、`會執行動作 否` |
| 53.2 呼叫者驗證 | 「XPC 自檢」＋ `xpc-probe` | ✅ `驗呼叫者 已啟用・驗 service 通過`；外部程序定址不到 |
| 53.3 sandbox profile | `./scripts/sandbox-verify.sh` | ✅ 7 項全綠、0 失敗、0 無效 |
| 53.4 `posix_spawn` 執行端 | CI（A 純值層）＋ 程式碼已接線（B）| ✅ A ・ B 由 53.5 翻開 |
| 53.7 記憶體診斷 | 選單取樣 + `MemoryLogWriter` 落檔，七輪收斂 | ✅ 定位並修復：**+151 → +7 MB/小時** |

### 三個不需要 Xcode 的驗收指令

```bash
./scripts/sandbox-verify.sh                       # 沙箱成對驗證（正向 + 負向）
swiftc -O -o /tmp/xpc-probe scripts/xpc-probe.swift && /tmp/xpc-probe   # 拒絕路徑
codesign -dv --verbose=4 "$(ls -d ~/Library/Developer/Xcode/DerivedData/CoPartner-*/Build/Products/Debug/CoPartner.app | head -1)/Contents/XPCServices/CoPartnerExecutor.xpc"
```

第三行是簽章檢查：`.xpc` 的 `TeamIdentifier` 必須與 app 相同。
若是 `not set`，`驗呼叫者` 會停在「未啟用」——巢狀程式碼沒跟外層同一身分簽。

### 🔒 還沒做的

> **開關已於 2026-08-20 翻開**（PR #30，53.5）。以下第 1 項就是它的驗收，做完回報即可標 ✅。
> 另外 53.6-B（UI 動作接線）已合併並通過真機乾跑，但 `willPerformUIActions` **仍為 `false`**——
> 翻開它是獨立的 53.6-C。

1. **第一次真的執行**（53.5 的驗收）：選單「執行測試」→ HUD 出現本地風險判定 → 按執行。
   **判定條件是 stdout 裡有那串隨機標記，不是 `didExecute == true`**——沙箱擋掉讀取時
   `cat` 照樣會結束、`didExecute` 照樣為真，stdout 卻是空的。稽核應出現 `attempt` + `executed` 兩筆。
2. **危險指令被攔**：提議 `rm -rf` → HUD 顯示紅色高風險 + 本地原因，且**不可**自動核准。
3. **kill-switch 全鏈**：接手到一半按 ⌃⌥⌘. → 串流斷、HUD 進 aborted、後續 token 全失效。
4. **越界寫入被 deny**：讓沙箱內動作寫工作目錄外 → 應失敗（`sandbox-verify.sh` 已驗過規則本身，
   這裡驗的是**真的接上執行端之後**仍然成立）。
5. **LiteLLM 預算熔斷**：`max_budget: 5` 跑到超額一次。
6. **接手品質**：留個 open loop → 熱鍵 → Claude 應**接續**而不是貼一堆說明文字。
   （前置：真雲端 SSE 來源尚未接上，目前串流解析鏈是用假來源驗的。）
7. **UI 動作乾跑對照**（53.6-C 翻開前）：選單「UI 乾跑」→ 核對宣告尺寸／實際尺寸／全域原點／
   換算後的落點，以及**那個位置上的 AX 元件**。座標算錯不會報錯，那一行是唯一能事前看出差別的東西。

### 更正的三個假設（原文有誤，別再照著做）

| 原文說 | 實際 |
|---|---|
| 「computer-use 契約預設值很可能過時，開工第一件事是查」 | **查過了，兩個值都是對的。** 真正的缺口是少了 API 必填欄位 |
| 「XPC service（`_ambient` 低權 user）」 | **做不到。** 內嵌 XPC service 必然與主 app 同 uid（實測 euid 501）。真正的圍籬在 sbpl |
| 「先驗 `sandbox-exec` 在你的 macOS 版本仍可用」 | **已驗，可用。** 威脅模型 §6 備援不需啟用 |

### 回報時請附

I1–I10 每條過沒過；`sandbox-verify.sh` 的完整輸出（它會自己說哪條無效）；
kill-switch 是不是**真的全鏈**斷；以及 Claude 有沒有正確續寫 open loop。

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
