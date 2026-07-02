# CoPartner 實作待辦清單（Step-by-Step TDD Backlog）

> 目的：把 M0–M6 拆成能一個一個交代「完成 step N」的顆粒度，每步都是 TDD（先寫測試、再實作到綠燈）。
> 搭配 `docs/planning/dev-execution-plan.md`（模型分工/時程/費用）與 `docs/roadmap.md`（里程碑總覽）一起讀。

## 使用方式

跟我說「**完成 step N**」，我就只做那一步，流程固定：

1. 確認前置 step 都已 ✅（沒有就先說明或停下來問）。
2. **先寫測試**（TDD red）——本文件已為每個近期 step 列好測試檔案與案例；照著寫。
3. 實作到測試綠燈（TDD green），必要時小重構（refactor）。
4. push 到 `claude/loving-darwin-Ka636`，靠 CI（macOS-15 runner）跑 `swift build` + `swift test` 驗證——見下方「重要限制」。
5. 回來更新本文件：該 step 狀態改 ✅（或 🔒，見下）、更新「進度總覽」表。
6. Conventional Commit（`feat:`/`test:`/`fix:` 等，依 `CONTRIBUTING.md`）。
7. 簡短回報做了什麼、CI 是否綠、有沒有需要你在真機驗證的部分。

不會跳著做（除非你要求）——依賴關係見每個 step 的「前置」欄。

## 重要限制（誠實說明）

我目前執行環境是 Linux 容器，**無法**：

- 編譯 Swift / 跑 `swift test`（只能 push 後靠 CI 的 macOS runner 驗證綠燈）
- 存取 macOS-only framework 的**執行期行為**：ScreenCaptureKit 實際擷取、Metal GPU dispatch、Accessibility API、FoundationModels 可用性、TCC 權限彈窗
- 量測真機數字：CPU%、延遲、記憶體、漏抓率

所以每個 step 的完成定義分兩種，並在標題列標注：

| 標記 | 意義 |
|---|---|
| ⬜ 未開始 |  |
| 🔄 進行中 |  |
| ✅ **CI 驗證完成** | 純邏輯/資料結構/演算法，已寫成 XCTest（或 pytest），CI 綠燈即代表完成，我可以自主判定 |
| 🔒 **需要你在真機驗證** | 牽涉真實螢幕擷取、TCC 權限、GPU、FoundationModels 執行期、UX 觀感——我會把「可測試邏輯」與「平台膠水代碼」分開，邏輯照樣有測試，但膠水代碼跑不跑得動、真機數字如何，需要你在 Mac 上跑過回報 |

**設計原則**：每個 step 我都會盡量把「膠水代碼」（真的呼叫 SCStream / AXUIElement / FoundationModels 的那幾行）獨立成薄薄一層、行為抽成 protocol，讓「決策邏輯」單獨可測。這樣即使我永遠不能跑真機，專案的正確性核心還是有測試守住。

## Rolling-wave 規劃原則

**M0–M2.5 已展開到完整 TDD 顆粒度**（測試檔名、案例、函式簽章都寫好，可以直接開工）。
**M3–M6 先給清楚的目標/交付物/DoD**，但不提前寫死詳細測試案例——因為 M0/M1 真機驗證結果（SCK dirtyRects 實際可靠性、FoundationModels 實際行為）很可能影響後面設計細節，太早寫死 test case 容易跟現實脫節。**開始某個里程碑的第一個 step 前，我會先做一次「展開」**，把那個里程碑的 step 補到跟 M0–M2.5 一樣詳細，再開工。這不是偷懶，是避免現在花力氣寫五個月後可能要改的規格。

## 分支與 commit

沿用目前工作分支 `claude/loving-darwin-Ka636`（不開新分支，依 session 既有指示）。每個 step 完成後至少一個 commit，訊息帶上 step 編號，例如：`test(capture): AttentionModel 回歸測試（step 1）`。

---

## 進度總覽

| # | Step | 里程碑 | 建議模型 | 狀態 | 前置 |
|---|---|---|---|---|---|
| 1 | AttentionModel 回歸測試 + 時鐘注入 | M0 | Sonnet 5 | ⬜ | — |
| 2 | Tile 座標與幾何工具 | M0 | Sonnet 5 | ⬜ | — |
| 3 | Metal dHash 差異比對邏輯（純 Swift）+ shader 骨架 | M0 | Sonnet 5 / 🔮Fable 5(shader) | ⬜ | 2 |
| 4 | SCStream dirtyRects 解析與可靠性防禦 | M0 | Opus 4.8 | ⬜ | 2, 3 |
| 5 | CaptureEngine.start()/stop() 串接 | M0 | Sonnet 5 | ⬜ | 1, 4 |
| 6 | CGEventTap → AttentionModel 事件橋接 | M0 | Sonnet 5 | ⬜ | 1 |
| 7 | AXUIElement 焦點區域擷取 | M0 | Sonnet 5 | ⬜ | 2 |
| 8 | 多解析度金字塔參數 | M0 | Sonnet 5 | ⬜ | 1 |
| 9 | 量測工具（CPU/延遲/漏抓率 harness） | M0 | Sonnet 5 | ⬜ | 5 |
| 10 | 🔒 M0 真機驗收 | M0 | — | ⬜ | 5, 6, 7, 8, 9 |
| 11 | Tile 狀態機核心（COLD/WARM/HOT/DYNAMIC） | M1 | Sonnet 5 / Opus 4.8 | ⬜ | 3, 4 |
| 12 | DYNAMIC 週期性偵測 | M1 | Opus 4.8 | ⬜ | 11 |
| 13 | 每 app override 清單 | M1 | Sonnet 5 | ⬜ | 11 |
| 14 | OCR/持久化節流串接 | M1 | Sonnet 5 | ⬜ | 11 |
| 15 | CaptureEngine 全狀態機整合 | M1 | Sonnet 5 | ⬜ | 5, 11 |
| 16 | 🔒 M1 真機驗收 | M1 | — | ⬜ | 12, 13, 14, 15 |
| 17 | Vision OCR wrapper（ROI） | M2 | Sonnet 5 | ⬜ | 2 |
| 18 | AX-text-first fallback 邏輯 | M2 | Sonnet 5 | ⬜ | 7 |
| 19 | sidecar `/ocr` 接線（ocrmac） | M2 | Sonnet 5 | ⬜ | — |
| 20 | CI 補 Python pytest job | M2 | Sonnet 5 | ⬜ | 19 |
| 21 | 🔒 M2 真機驗收 | M2 | — | ⬜ | 17, 18, 19 |
| 22 | L0 事件模板格式化器 | M2.5 | Sonnet 5 | ⬜ | — |
| 23 | 合併規則（打字合併/scroll 節流） | M2.5 | Sonnet 5 | ⬜ | 22 |
| 24 | PII 遮罩（貼上/剪下前置遮罩） | M2.5 | Opus 4.8 | ⬜ | 22 |
| 25 | L0 完整性驗收（劇本重現操作） | M2.5 | Sonnet 5 | ⬜ | 22, 23, 24 |
| 26 | 【展開】M3 詳細 step 規劃 | M3 | Opus 4.8 | ⬜ | 10, 16 |
| 27 | Reference+delta 重建演算法 | M3 | Sonnet 5 / Opus 4.8審 | ⬜ | 26 |
| 28 | L1 RAM ring buffer | M3 | Sonnet 5 | ⬜ | 26 |
| 29 | sqlite-vec schema + KNN wrapper | M3 | Opus 4.8 | ⬜ | 26 |
| 30 | Re-baseline 觸發邏輯 | M3 | Sonnet 5 | ⬜ | 27 |
| 31 | 注意力熱圖（衰減式） | M3 | Sonnet 5 | ⬜ | 26 |
| 32 | 🔒 M3 真機驗收 | M3 | — | ⬜ | 27–31 |
| 33 | 【展開】M4 詳細 step 規劃 | M4 | Opus 4.8 | ⬜ | 32 |
| 34 | FoundationModels L1 Narrator 接線 | M4 | Opus 4.8 | ⬜ | 33 |
| 35 | Availability + fallback 階梯 | M4 | Opus 4.8 | ⬜ | 34 |
| 36 | L2 Summarizer | M4 | Sonnet 5 | ⬜ | 34 |
| 37 | sidecar `/vlm` 接 mlx-vlm | M4 | Opus 4.8 | ⬜ | 33 |
| 38 | 🔒 M4 真機驗收 | M4 | — | ⬜ | 34–37 |
| 39 | 【展開】M5 詳細 step 規劃 | M5 | Fable 5 | ⬜ | 38 |
| 40 | ContextEnvelope 打包邏輯 | M5 | Sonnet 5 | ⬜ | 39 |
| 41 | PII 出境閘門整合 | M5 | Opus 4.8 | ⬜ | 24, 40 |
| 42 | LiteLLM Gateway 設定 | M5 | Sonnet 5 | ⬜ | 39 |
| 43 | CloudRouter.handoff() 接 Claude computer-use | M5 | Fable 5 | ⬜ | 40, 41, 42 |
| 44 | 風險分級 + 危險指令偵測 | M5 | Opus 4.8 | ⬜ | 39 |
| 45 | ActionExecutor 沙箱（XPC + sandbox-exec） | M5 | Fable 5 | ⬜ | 44 |
| 46 | Undo stack | M5 | Sonnet 5 | ⬜ | 45 |
| 47 | 🔒 M5 真機驗收 | M5 | — | ⬜ | 43, 45, 46 |
| 48 | 【展開】M6 詳細 step 規劃 | M6 | Opus 4.8 | ⬜ | 47 |
| 49 | tile 級遮罩（PII regex + AX secure field） | M6 | Opus 4.8 | ⬜ | 48 |
| 50 | SCContentFilter 黑名單 | M6 | Sonnet 5 | ⬜ | 48 |
| 51 | 熱圖隱私串接 | M6 | Sonnet 5 | ⬜ | 31, 49 |
| 52 | 🔒 M6 真機驗收（PIPL 最終審查） | M6 | — | ⬜ | 49–51 |

---

## M0 — 擷取引擎原型

延續設計：`docs/design/v2_smart-capture-engine.md §B`，採 §M 建議的 **Tier 2 簡化路徑**（滑鼠/焦點 attention region 高頻高解析 + 周邊定頻縮圖，先不做完整 tile 狀態機——那是 M1）。

#### Step 1 — AttentionModel 回歸測試 + 時鐘注入
- **背景**：`AttentionModel`（ADR-0006）已實作但**零測試**。它內部用 `Date()` 算衰減，無法決定性測試——先做和 `EscalationPolicy.decide(_:now:)` 一樣的 `now:` 參數注入（小重構），再補測試。
- **修改檔案**：`packages/CoPartnerKit/Sources/CaptureEngine/CaptureEngine.swift`（`update`/`captureParams`/`decay` 加 `now: Date = Date()` 參數）；`packages/CoPartnerKit/Package.swift`（`CoPartnerKitTests` 依賴加入 `"CaptureEngine"`，目前沒有這條，測試會過不了 import）
- **新增測試**（`Tests/CoPartnerKitTests/AttentionModelTests.swift`）：
  - `testClickSetsEnergyToPeakAndReturnsTrue`
  - `testIdleReturnsFalseAndDoesNotForceCapture`
  - `testHighSpeedMoveStaysBelowHotBand`
  - `testDragMaintainsAtLeast085Energy` / `testScrollMaintainsAtLeast06Energy`
  - `testEnergyDecaysAcrossHalfLife`（用注入的 `now` 前進 2s，斷言能量約略減半）
  - `testEnergyBandThresholds`（0.7 / 0.4 / 0.15 邊界各測一次）
  - `testPointUpdatesCenterRegardlessOfSignal`
- **建議模型**：Sonnet 5
- **DoD**：✅ CI 綠燈

#### Step 2 — Tile 座標與幾何工具
- **目標**：tile-grid 純數學（螢幕座標↔tile 索引、rect↔tile 範圍），供 dirty-rect 對應與 Metal hash 定址共用。
- **新增檔案**：`Sources/CaptureEngine/TileGrid.swift`（`struct TileGrid`：`tileSize`(預設 128px)/`cols`/`rows`，`tileIndex(for:)`、`tiles(overlapping:)`、`rect(forTileX:y:)`）
- **新增測試**（`TileGridTests.swift`）：
  - `testTileIndexAtOrigin` / `testTileIndexAtExactBoundary`
  - `testTilesOverlappingRectSpanningMultipleTiles`
  - `testTilesOverlappingRectClampsToGridBounds`（超出螢幕邊界的 rect）
  - `testRectForTileRoundTrip`
- **建議模型**：Sonnet 5
- **DoD**：✅ CI 綠燈（純邏輯，無平台依賴）

#### Step 3 — Metal dHash 差異比對邏輯 + shader 骨架
- **目標**：把「可測」與「不可測」拆乾淨。可測部分：兩組 hash 的 Hamming distance 與變動分級；不可測部分：真正的 GPU shader。
- **新增檔案**：
  - `Sources/CaptureEngine/TileHashDiff.swift`（`func hammingDistance(_:_:) -> Int`；`enum ChangeMagnitude { none, small, large }`；`func classify(distance:thresholds:) -> ChangeMagnitude`）
  - `Sources/CaptureEngine/Resources/TileHash.metal`（🔒 shader 骨架，per-threadgroup 輸出 uint64，無法在 CI 跑，僅手動審閱正確性）
- **新增測試**（`TileHashDiffTests.swift`）：
  - `testIdenticalHashesZeroDistance`
  - `testHammingDistanceKnownBitPatterns`
  - `testSmallDistanceClassifiedAsCursorResidue` / `testLargeDistanceClassifiedAsRealChange`
  - `testClassifyThresholdBoundaries`
- **建議模型**：Sonnet 5 寫 Swift 邏輯；`.metal` shader 本身無先例可抄、無法用 CI 迭代除錯，**建議 Fable 5** 起草（一次把邏輯想清楚，比事後在真機慢慢除錯划算）
- **DoD**：Swift 部分 ✅ CI 綠燈；`.metal` 🔒 留待 Step 10 真機驗收時檢查

#### Step 4 — SCStream dirtyRects 解析與可靠性防禦
- **目標**：對抗 §B.1 已知陷阱（status 常回 idle、dirtyRects 可能空、Sequoia 15.6.1 contentRect X=48 bug）。用 protocol 抽象 SCK，讓決策邏輯可測。
- **新增檔案**：
  - `Sources/CaptureEngine/DirtyRegionResolver.swift`：`protocol FrameInfoProviding { dirtyRects, status, contentRect }`、`enum FrameStatus`、`struct DirtyRegionResolver`（融合 SCK 訊號 + Metal hash，任一方回報變動就採信——「Metal hash 永遠當 ground truth」）
  - `Sources/CaptureEngine/ScreenCaptureSource.swift`（🔒 真正 `SCStream` 包裝，adapt 成 `FrameInfoProviding`）
- **新增測試**（`DirtyRegionResolverTests.swift`）：
  - `testDirtyRectsMapToCorrectTiles`
  - `testIdleStatusFallsBackToHashDiffOnly`（status=idle 但 hash 有差異 → 仍回報變動，防 SCK 說謊）
  - `testEmptyDirtyRectsWithUnchangedHashesReportsNoChange`
  - `testEmptyDirtyRectsButHashChangedStillReportsChange`
  - `testMultipleDirtyRectsAggregateOverlappingTiles`
- **建議模型**：**Opus 4.8**（全 M0 邏輯最容易藏 bug 的一段——對抗已知平台陷阱）
- **DoD**：resolver 邏輯 ✅ CI 綠燈（用假 `FrameInfoProviding`）；`ScreenCaptureSource` 🔒 真機驗收

#### Step 5 — CaptureEngine.start()/stop() 串接
- **目標**：把 `AttentionModel` + `TileGrid` + `DirtyRegionResolver` 接進 `CaptureEngine` actor，`start()` 開始產生 `TileEvent` 串流（`AsyncStream<TileEvent>`），`stop()` 停止。
- **修改檔案**：`Sources/CaptureEngine/CaptureEngine.swift`
- **新增測試**（`CaptureEngineTests.swift`）：用假的 frame 來源驅動 `start()`，斷言吐出的 `TileEvent` 符合預期；`stop()` 後不再吐新事件。
- **建議模型**：Sonnet 5
- **DoD**：✅ CI 綠燈（假來源）；真正接 `ScreenCaptureSource` 🔒 隨 Step 10

#### Step 6 — CGEventTap → AttentionModel 事件橋接
- **目標**：把 `CGEventType`（`.leftMouseDown`/`.mouseMoved`/`.leftMouseDragged`/`.scrollWheel`/`.keyDown`）映射成 `AttentionModel.Signal`。膠水（`CGEvent.tapCreate`，需 Input Monitoring 權限）與映射邏輯分開。
- **新增檔案**：`Sources/CaptureEngine/EventTapMapper.swift`（純函式 `func signal(for:mouseDelta:) -> AttentionModel.Signal?`）+ 🔒 `Sources/CaptureEngine/InputEventTap.swift`（真正 tap）
- **新增測試**（`EventTapMapperTests.swift`）：每個 `CGEventType` 對應正確 `Signal`；未知類型回 `nil`。
- **建議模型**：Sonnet 5
- **DoD**：mapper ✅ CI 綠燈；tap 本身 🔒

#### Step 7 — AXUIElement 焦點區域擷取
- **目標**：§B.4 焦點元件定義重點區域。抽 `protocol AXFocusProviding`，可測「給定 AX 屬性 → 算出焦點區 CGRect」。
- **新增檔案**：`Sources/CaptureEngine/FocusRegionResolver.swift` + 🔒 `Sources/CaptureEngine/SystemAXFocusProvider.swift`
- **新增測試**：`FocusRegionResolverTests.swift`（假 provider 給不同 AXFrame，驗證區域計算）
- **建議模型**：Sonnet 5
- **DoD**：✅ CI 綠燈（假 provider）；真 AX 呼叫 🔒

#### Step 8 — 多解析度金字塔參數
- **目標**：§B.5 三層（L0 焦點原生 2x / L1 周邊 1x-0.5x / L2 概覽 ≤1024px）參數化，擴充 `AttentionModel.captureParams()` 的輸出或新增 `struct CapturePyramid`。
- **新增測試**：各能量帶對應正確的三層參數組合。
- **建議模型**：Sonnet 5
- **DoD**：✅ CI 綠燈

#### Step 9 — 量測工具（CPU/延遲/漏抓率 harness）
- **目標**：寫一個可在真機執行的量測工具（CLI 或內建 debug flag），把 CPU%、每幀延遲、tile 變動計數 dump 成 log，讓 Step 10 的真機驗收有數字可報。
- **建議模型**：Sonnet 5
- **DoD**：✅ 工具碼本身可 CI 編譯檢查；實際量測結果屬 🔒

#### Step 10 — 🔒 M0 真機驗收
- 打包簽章 `.app`（`scripts/permissions-check.sh` 先跑一次）、授權 Screen Recording/Accessibility/Input Monitoring、跑 Step 9 harness，量 CPU%/漏抓率/延遲，產出 V1 vs V2 對照數字（roadmap 驗收標準）。**這步要你在你的 Mac 上執行**，數字回報給我後我會記錄進本文件。

---

## M1 — 冷熱狀態機 + DYNAMIC

延續 `docs/design/v2_smart-capture-engine.md §B.6`。`TileEvent.State`（cold/warm/hot/dynamic）已在 `CoPartnerCore/Models.swift` 定義好，這個里程碑要做出真正驅動它的狀態機。

#### Step 11 — Tile 狀態機核心
- **目標**：純狀態轉換邏輯，輸入是「隨時間推進的 tile 變動分級序列」（吃 Step 3 的 `ChangeMagnitude`），輸出 `TileEvent.State` 轉換，規則見 §B.6 表格。
- **新增檔案**：`Sources/CaptureEngine/TileStateMachine.swift`
- **測試重點**：COLD 持續無變化維持 COLD；單次變化→WARM；持續變化→HOT；規律高頻大面積→DYNAMIC；**AX 可得文字的 tile 不套 DYNAMIC**（§L override，重要邊界案例）。
- **建議模型**：Sonnet 5 實作，**Opus 4.8** 審 DYNAMIC 誤判閾值（false positive/negative 取捨判斷重）
- **DoD**：✅ CI 綠燈

#### Step 12 — DYNAMIC 週期性偵測
- **目標**：偵測 tile 變動時間戳是否呈規律間隔（30/60fps 倍數），純邏輯可測（合成時間序列）。
- **建議模型**：Opus 4.8
- **DoD**：✅ CI 綠燈

#### Step 13 — 每 app override 清單
- **目標**：§L 風險緩解——允許 per-app 排除 DYNAMIC 判定（如股價 ticker 合法一直變但不是影片）。簡單設定結構 + 查詢邏輯。
- **建議模型**：Sonnet 5
- **DoD**：✅ CI 綠燈

#### Step 14 — OCR/持久化節流串接
- **目標**：狀態機輸出接到「該不該跑 OCR / 該不該存 delta」的節流決策（§B.6 表格：COLD 否/WARM dirty時/HOT 節流/DYNAMIC 否）。用假 OCR/persistence spy 驗證呼叫次數。
- **建議模型**：Sonnet 5
- **DoD**：✅ CI 綠燈

#### Step 15 — CaptureEngine 全狀態機整合
- **目標**：把 M0 的簡化 Tier 2 邏輯換成完整 per-tile 狀態機驅動擷取頻率/解析度。
- **建議模型**：Sonnet 5
- **DoD**：✅ CI 綠燈（假來源）；真機整合 🔒 隨 Step 16

#### Step 16 — 🔒 M1 真機驗收
- 播 1080p 影片，CPU 不超 baseline；影片正確標 DYNAMIC。你在真機跑，回報數字。

---

## M2 — 局部 OCR + AX 文字

#### Step 17 — Vision OCR wrapper（ROI）
- **目標**：`VNRecognizeTextRequest`（`.accurate`、zh-Hant+en-US、`regionOfInterest`）包裝。可測部分：給定 dirty tiles 列表 → 算出正確的 normalized ROI rect。
- **新增檔案**：`Sources/CaptureEngine/OCRRegionMapper.swift`（純邏輯）+ 🔒 真正 Vision 呼叫
- **建議模型**：Sonnet 5
- **DoD**：✅ CI 綠燈（ROI 計算）；真 OCR 準確度 🔒

#### Step 18 — AX-text-first fallback 邏輯
- **目標**：「能拿 AX 文字的 tile 不必跑 OCR」決策邏輯，用假 AX text provider 測試。
- **建議模型**：Sonnet 5
- **DoD**：✅ CI 綠燈

#### Step 19 — sidecar `/ocr` 接線（ocrmac）
- **目標**：把 `sidecar/copartner_sidecar/server.py` 已 stub 的 `/ocr` endpoint 接上 `ocrmac`。
- **建議模型**：Sonnet 5
- **DoD**：✅（需 Step 20 的 pytest 才能在 CI 驗證邏輯；ocrmac 實際辨識品質 🔒）

#### Step 20 — CI 補 Python pytest job
- **背景**：目前 `.github/workflows/ci.yml` 的 `python` job **只有 `ruff check`，完全沒有測試**。這是現有落差，這步順手補上。
- **修改檔案**：`sidecar/pyproject.toml`（加 `pytest` dev dependency）、新增 `sidecar/tests/`、`.github/workflows/ci.yml`（加 `uvx pytest` 步驟）
- **建議模型**：Sonnet 5
- **DoD**：✅ CI 綠燈

#### Step 21 — 🔒 M2 真機驗收
- OCR 像素吞吐 ≤ V1 的 20%。你在真機跑，回報數字。

---

## M2.5 — L0 EventLog

延續 `docs/design/v2.1_action-script-narrator.md §2`（格式範例、合併規則表已在該文件寫死，直接照抄）。`ScriptNarrator.swift` 目前已有 `EventLog` 骨架（只有 `append`）。

#### Step 22 — L0 事件模板格式化器
- **目標**：依 v2.1 §2 的行格式（`[HH:mm:ss.SSS] FOCUS app=... win=...` 等 6 種事件類型）寫格式化器。
- **新增檔案**：`Sources/ScriptNarrator/EventFormatter.swift`
- **測試重點**：6 種事件類型（FOCUS/TYPE/PASTE/SWITCH/SCROLL/WATCH）各自格式正確；時間戳精度到毫秒。
- **建議模型**：Sonnet 5
- **DoD**：✅ CI 綠燈

#### Step 23 — 合併規則（打字合併/scroll 節流）
- **目標**：同欄位 2 秒內文字輸入合併成一句；scroll 1 秒視窗聚合方向+距離。用注入 `now:` 的 clock（同 Step 1 模式）做決定性測試。
- **修改檔案**：`Sources/ScriptNarrator/ScriptNarrator.swift`（`EventLog.append` 擴充合併邏輯）
- **建議模型**：Sonnet 5
- **DoD**：✅ CI 綠燈

#### Step 24 — PII 遮罩（貼上/剪下前置遮罩）
- **目標**：套用 `docs/privacy/data-classification.md` 的 regex（TW 身分證/手機、CN 身分證）在**進入 L0 之前**遮罩貼上/剪下內容，例如 `[貼上疑似卡號，已遮罩]`。
- **測試重點**：已知 PII pattern 必須被遮；非 PII 內容不誤傷；preview 截斷長度正確。
- **建議模型**：**Opus 4.8**（隱私關鍵路徑，漏遮 = PII 進劇本）
- **DoD**：✅ CI 綠燈

#### Step 25 — L0 完整性驗收（劇本重現操作）
- **目標**：整合測試——餵一段模擬操作序列（focus/type/paste/switch/scroll）進 L0 pipeline，斷言輸出的 log 讓人能重建操作過程。對應 roadmap 驗收「劇本完整重現一段操作（時間機器）」。
- **建議模型**：Sonnet 5
- **DoD**：✅ CI 綠燈——**這是 M2.5 唯一不需要 🔒 真機驗收的里程碑**（L0 全是本地確定性邏輯，無 GPU/AX/FoundationModels 依賴）

---

## M3 — 記憶系統（rolling-wave：先列目標，開工前 Step 26 展開細節）

延續 §C（三層記憶）+ v2.1 §3（劇本=檢索主幹）。`MemoryStore.swift` 已有 `insert`/`search` 空殼。

#### Step 26 — 【展開】M3 詳細 step 規劃
- 開始 M3 前，先根據 M0/M1 真機驗證結果（尤其 tile hash 產出的實際資料量），把下面 5 個 step 展開成跟 M0 一樣的完整測試案例清單。
- **建議模型**：Opus 4.8

#### Step 27 — Reference+delta 重建演算法
- **目標**：I-frame/P-frame 模型（§B.7）——維護 reference + 一串 delta，能重建任一時間點畫面。**資料正確性風險最高的一步**（重建錯 = 靜默資料損毀），純演算法可測。
- **建議模型**：Sonnet 5 實作，**Opus 4.8 審查**重建正確性
- **DoD**：✅ CI 綠燈（先於 Step 26 展開時補齊 test case）

#### Step 28 — L1 RAM ring buffer
- **目標**：時間窗限制的記憶體暫存（最近 5–15 分鐘熱劇本，v2.1 §3）。
- **建議模型**：Sonnet 5

#### Step 29 — sqlite-vec schema + KNN wrapper
- **目標**：`vec0` 虛擬表（float[768]）+ `MemoryStore.insert`/`search` 真正實作。膠水（載入 sqlite-vec extension）🔒，query/ranking 邏輯可測。
- **修改檔案**：`packages/CoPartnerKit/Package.swift`（`CoPartnerKitTests` 依賴需加入 `"MemoryStore"`）
- **建議模型**：Opus 4.8（schema 設計 + extension 載入容易踩坑）

#### Step 30 — Re-baseline 觸發邏輯
- **目標**：每 T 秒或累積 delta 超過畫面 X% 時觸發 re-baseline，純邏輯可測。
- **建議模型**：Sonnet 5

#### Step 31 — 注意力熱圖（衰減式）
- **目標**：tile grid 衰減式 heatmap，只存聚合權重（§G 隱私要求：不存原始座標時序）。
- **建議模型**：Sonnet 5

#### Step 32 — 🔒 M3 真機驗收
- 8hr 磁碟 ≤ ~400MB；語意檢索可用。你在真機跑，回報數字。

---

## M4 — 本地推理（rolling-wave）

`ScriptNarrator.swift` 的 `Narrator.narrate()` 目前回傳固定 `nil`——這裡要真正接上。

#### Step 33 — 【展開】M4 詳細 step 規劃
- **建議模型**：Opus 4.8

#### Step 34 — FoundationModels L1 Narrator 接線
- **目標**：接 `LanguageModelSession` + `@Generable ActionStep` + `prewarm()`（v2.1 §2 已有完整程式碼範例可直接參考改寫）。
- **建議模型**：Opus 4.8（新 API，容易踩 availability/型別坑）

#### Step 35 — Availability + fallback 階梯
- **目標**：FoundationModels 不可用 → Qwen MLX → 規則式模板（§5 三階 fallback）。可測：給定假 availability 狀態，斷言選對 fallback 路徑。
- **建議模型**：Opus 4.8

#### Step 36 — L2 Summarizer
- **目標**：切 app / 數分鐘 rollup 成段落摘要。
- **建議模型**：Sonnet 5

#### Step 37 — sidecar `/vlm` 接 mlx-vlm
- **目標**：真正載入 `mlx-community/Qwen2.5-VL-7B-Instruct-4bit` 並 generate。
- **建議模型**：Opus 4.8

#### Step 38 — 🔒 M4 真機驗收
- 本地路徑 sub-second；L1 意圖準確率主觀評估；FoundationModels 實際 availability 行為（新 API，只有真機能驗）。

---

## M5 — 雲端 + 動作 + 交棒（rolling-wave，全案第二高風險）

`CloudRouter.handoff()`、`ActionExecutor.execute()` 目前都是空殼。

#### Step 39 — 【展開】M5 詳細 step 規劃
- 這是全專案風險第二高的里程碑（AI 發指令、sandbox 執行），展開時建議先寫一份沙箱威脅模型草稿再拆 step。
- **建議模型**：**Fable 5**

#### Step 40 — ContextEnvelope 打包邏輯
- **目標**：v2.1 §4.1 已有完整 JSON 範例，照結構打包（劇本為主體 + 焦點小圖 + AX + 剪貼簿 + takeover contract）。
- **建議模型**：Sonnet 5

#### Step 41 — PII 出境閘門整合
- **目標**：Presidio + 資料分類表規則，出境前最後一道檢查（接 Step 24 的遮罩邏輯）。
- **建議模型**：Opus 4.8（隱私關鍵）

#### Step 42 — LiteLLM Gateway 設定
- **目標**：Docker 化 LiteLLM，PIPL guard 路由規則（含上海個資 → local-only 強制不出境）。
- **建議模型**：Sonnet 5

#### Step 43 — CloudRouter.handoff() 接 Claude computer-use
- **目標**：beta header `computer-use-2025-11-24`、tool `computer_20251124`、Retina 座標 ÷2、prompt caching 穩定前綴。
- **建議模型**：**Fable 5**（新協定整合，細節多且一次要對）

#### Step 44 — 風險分級 + 危險指令偵測
- **目標**：`rm -rf`/`sudo`/`git push -f`/`dd`/`curl|sh` 等 pattern 偵測，強制 confirm-each。純字串/pattern 邏輯可測。
- **建議模型**：Opus 4.8

#### Step 45 — ActionExecutor 沙箱（XPC + sandbox-exec）
- **目標**：`_ambient` unprivileged user + sandbox-exec sbpl profile（限 network/exec/file write）。
- **修改檔案**：`packages/CoPartnerKit/Package.swift`（`CoPartnerKitTests` 依賴需加入 `"ActionExecutor"`）
- **建議模型**：**Fable 5**（安全邊界設計錯了就是真的漏洞）

#### Step 46 — Undo stack
- **目標**：git stash / APFS snapshot / AX tree snapshot 三種 undo 機制。
- **建議模型**：Sonnet 5

#### Step 47 — 🔒 M5 真機驗收
- 熱鍵後 Claude 正確接續 open loop；高風險動作強制確認。

---

## M6 — 隱私 + 黑名單（rolling-wave）

#### Step 48 — 【展開】M6 詳細 step 規劃
- **建議模型**：Opus 4.8

#### Step 49 — tile 級遮罩（PII regex + AX secure field）
- **目標**：`kAXSecureTextField` + URL/標題啟發式 + OCR 正則（卡號/身分證/API key）。
- **建議模型**：Opus 4.8（漏遮 = PII 外洩）

#### Step 50 — SCContentFilter 黑名單
- **目標**：白名單 `includingApplications` 實作（避開空陣列 bug）、排除自身 app。
- **建議模型**：Sonnet 5

#### Step 51 — 熱圖隱私串接
- **目標**：串接 Step 31 熱圖與遮罩規則，確保聚合權重也不洩漏敏感區域。
- **建議模型**：Sonnet 5

#### Step 52 — 🔒 M6 真機驗收（PIPL 最終審查）
- 密碼欄/銀行頁 100% 被遮；黑名單 app 0 frame。全案完整跑一輪隱私稽核。

---

## 完成後

52 步做完 = M0–M6 全部落地，對應 `docs/roadmap.md` 的完整 V2 願景。到時候再一起看要不要規劃 V3（例如 App Store 上架、多人協作等），不在本文件範圍內。

現在可以說「**完成 step 1**」開始。
