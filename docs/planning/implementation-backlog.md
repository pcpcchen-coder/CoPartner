# CoPartner 實作待辦清單（Step-by-Step TDD Backlog）

> 目的：把整個專案拆成能一個一個交代「完成 step N」的顆粒度，每步都是 TDD（先寫測試、再實作到綠燈）。
> 搭配 `docs/planning/dev-execution-plan.md`（模型分工/時程/費用）與 `docs/roadmap.md`（里程碑總覽）一起讀。

## 修訂說明（v3，2026-07-02）

這份清單以「最終成品」為準重新檢視過一次。大目標是一個**類 Siri × ChatGPT × Claude Desktop 的常駐工具**：使用者開啟後它持續理解操作習慣，下達接手命令後由 AI 接手工作，並依任務難易度在本地/雲端模型間路由。對照這個目標，v2 版清單有三個缺口，v3 修正如下：

1. **原清單完全沒碰 `apps/CoPartner/`**。menu bar app 骨架（`CoPartnerApp` / `AppCoordinator` / `MenuBarContentView`）其實已存在，但 `toggleObserving()`、`triggerIntervention()` 都是空殼，`KeyboardShortcuts` 依賴宣告了卻沒有任何 target 使用，緊急停止與接手 HUD 都還沒接。「開啟後就運作」「下達接手命令」這個**產品核心**原本不在計畫裡 → v3 新增 **應用外殼與互動層** 的 step，並讓 CI 真的建置 app target。
2. **開發順序**：依你的選擇「加入早期可跑骨架」，把 L0 操作劇本（只需 Input Monitoring + Accessibility，**不需** ScreenCaptureKit/Metal）提前到 **Phase A**，接進既有 menu bar app → 幾週內就有一個可 dogfood 的「操作時間機器」；最難、最依賴真機的螢幕擷取（SCStream/Metal）改成疊在「已經會跑的東西」上面。
3. **語音（Siri 那一面）**：依你的選擇 **延後到 V3**。M0–M6 維持純螢幕範圍；語音全日轉錄摘要 + 語音交棒記在文末「V3 展望」，不進這輪待辦。

編號已重排成單一線性序列（Phase A→G），你可以直接說「完成 step 1」「完成 step 2」。沒有任何 step 已開工，重排零成本。

## 使用方式

跟我說「**完成 step N**」，我就只做那一步，流程固定：

1. 確認前置 step 都已 ✅（沒有就先說明或停下來問）。
2. **先寫測試**（TDD red）——近期 step 已列好測試檔案與案例；照著寫。
3. 實作到測試綠燈（TDD green），必要時小重構。
4. push 到 `claude/loving-darwin-Ka636`，靠 CI（macOS-15 runner）驗證——見「重要限制」。
5. 回來更新本文件狀態欄 + 進度總覽表。
6. Conventional Commit，訊息帶 step 編號（如 `test(capture): AttentionModel 回歸測試（step 2）`）。
7. 簡短回報做了什麼、CI 是否綠、有沒有需要你在真機驗證的部分。

不會跳著做（除非你要求）——依賴見每步「前置」欄。

## 重要限制（誠實說明）

我的執行環境是 Linux 容器，**無法**：編譯 Swift / 跑 `swift test`（只能 push 後靠 CI 的 macOS runner）、存取 macOS-only framework 的執行期行為（ScreenCaptureKit 實際擷取、Metal GPU、Accessibility、FoundationModels、TCC 權限彈窗、KeyboardShortcuts 全域熱鍵實際觸發）、量測真機數字（CPU%/延遲/記憶體/漏抓率）。

所以每步的完成定義分兩種，標題會標注：

| 標記 | 意義 |
|---|---|
| ⬜ 未開始 / 🔄 進行中 |  |
| ✅ **CI 驗證完成** | 純邏輯/資料結構/演算法/view-model，寫成 XCTest（或 pytest），CI 綠燈即完成，我可自主判定 |
| 🔒 **需要你在真機驗證** | 牽涉真實擷取、TCC 權限、GPU、FoundationModels 執行期、全域熱鍵、UX 觀感——我把「可測邏輯」與「平台膠水」拆開，邏輯照樣有測試，但膠水跑不跑得動、真機數字如何，需要你在 Mac 上回報 |

**設計原則**：每步都盡量把「膠水代碼」（真的呼叫 SCStream / AXUIElement / FoundationModels / CGEventTap 的那幾行）抽成薄薄一層 + protocol，讓「決策邏輯」單獨可測。即使我永遠不能跑真機，正確性核心仍有測試守住。

## Rolling-wave 規劃原則

**Phase A–C 已展開到完整 TDD 顆粒度**（測試檔名、案例、簽章都寫好，可直接開工）。**Phase D–G 先給清楚的目標/交付物/DoD**，但不提前寫死詳細測試案例——因為 Phase A/B 真機驗證結果（SCK dirtyRects 實際可靠性、FoundationModels 實際行為）很可能影響後面細節。**每個 rolling-wave 階段的第一個 step 是「展開」**，開工前先把該階段 step 補到跟 Phase A 一樣詳細再動手。

## 分支與 commit

沿用工作分支 `claude/loving-darwin-Ka636`（不開新分支）。每步至少一個 commit，訊息帶 step 編號。

---

## 進度總覽

| # | Step | 里程碑 | 建議模型 | 狀態 | 前置 |
|---|---|---|---|---|---|
| **A. 可跑骨架 — 操作時間機器（先讓它能開來用）** ||||||
| 1 | CI 建置 app target（xcodegen + xcodebuild） | 基建 | Sonnet 5 | ✅ | — |
| 2 | AttentionModel 回歸測試 + 時鐘注入 | M0 | Sonnet 5 | ✅ | — |
| 3 | CGEventTap → Signal 映射器（+ 🔒 真 tap 膠水） | M0 | Sonnet 5 | ✅ | 2 |
| 4 | AX 焦點區域解析（+ 🔒 真 AX 膠水） | M0 | Sonnet 5 | ✅ | — |
| 5 | L0 事件模板格式化器 | M2.5 | Sonnet 5 | ✅ | — |
| 6 | L0 合併規則（打字合併 / scroll 節流） | M2.5 | Sonnet 5 | ✅ | 5 |
| 7 | L0 PII 遮罩（貼上/剪下前置遮罩） | M2.5 | Opus 4.8 | ✅ | 5 |
| 8 | 即時事件日誌 view-model + 接進 menu bar | 應用層 | Sonnet 5 | ✅ | 3,4,6,7 |
| 9 | 緊急停止（⌃⌥⌘.）+ 觀察開關（⌃⌥⌘O）真接線 | 應用層 | Opus 4.8 | ✅ | 8 |
| 10 | 🔒 可跑骨架 dogfood 驗收（操作時間機器） | M2.5 | — | ✅ 真機通過 | 8,9 |
| 10.5 | 使用者可設定熱鍵（KeyboardShortcuts.Recorder 設定視窗）+ 放大操作劇本區 | 應用層 | Sonnet 5 | ✅ 真機通過 | 9,10 |
| **B. 智慧擷取引擎（把螢幕視覺疊上會跑的東西）** ||||||
| 11 | Tile 座標與幾何工具 | M0 | Sonnet 5 | ✅ | — |
| 12 | Metal dHash 差異比對邏輯 + 🔒 shader 骨架 | M0 | Fable 5（全步） | ✅ | 11 |
| 13 | SCStream dirtyRects 解析與可靠性防禦 | M0 | Opus 4.8 | ⬜ | 11,12 |
| 14 | ScreenCaptureSource 膠水 + CaptureEngine 串接 | M0 | Sonnet 5 | ⬜ | 2,13 |
| 15 | 多解析度金字塔參數 | M0 | Sonnet 5 | ⬜ | 2 |
| 16 | 擷取接進 app（視覺脈絡疊加事件日誌） | 應用層 | Sonnet 5 | ⬜ | 8,14 |
| 17 | 量測 harness（CPU/延遲/漏抓率） | M0 | Sonnet 5 | ⬜ | 14 |
| 18 | 🔒 M0 真機驗收（V1 vs V2 對照） | M0 | — | ⬜ | 14,15,16,17 |
| 19 | Tile 狀態機（COLD/WARM/HOT/DYNAMIC） | M1 | Sonnet 5 / Opus 審 | ⬜ | 12,13 |
| 20 | DYNAMIC 週期性偵測 | M1 | Opus 4.8 | ⬜ | 19 |
| 21 | 每 app override 清單 | M1 | Sonnet 5 | ⬜ | 19 |
| 22 | OCR/持久化節流串接 | M1 | Sonnet 5 | ⬜ | 19 |
| 23 | CaptureEngine 全狀態機整合 | M1 | Sonnet 5 | ⬜ | 14,19 |
| 24 | 🔒 M1 真機驗收（1080p 影片 CPU） | M1 | — | ⬜ | 20,21,22,23 |
| **C. 局部 OCR + AX 文字** ||||||
| 25 | Vision OCR ROI 映射器（+ 🔒 真 OCR） | M2 | Sonnet 5 | ⬜ | 11 |
| 26 | AX-text-first fallback 邏輯 | M2 | Sonnet 5 | ⬜ | 4 |
| 27 | sidecar `/ocr` 接線（ocrmac） | M2 | Sonnet 5 | ⬜ | — |
| 28 | CI 補 Python pytest job | 基建 | Sonnet 5 | ⬜ | 27 |
| 29 | 🔒 M2 真機驗收（OCR 吞吐 ≤ V1 20%） | M2 | — | ⬜ | 25,26,27 |
| **D. 記憶系統（rolling-wave）** ||||||
| 30 | 【展開】D 階段詳細 step 規劃 | M3 | Opus 4.8 | ⬜ | 18,24 |
| 31 | Reference+delta 重建演算法 | M3 | Sonnet 5 / Opus 審 | ⬜ | 30 |
| 32 | L1 RAM ring buffer | M3 | Sonnet 5 | ⬜ | 30 |
| 33 | sqlite-vec schema + KNN wrapper | M3 | Opus 4.8 | ⬜ | 30 |
| 34 | Re-baseline 觸發邏輯 | M3 | Sonnet 5 | ⬜ | 31 |
| 35 | 注意力熱圖（衰減式） | M3 | Sonnet 5 | ⬜ | 30 |
| 36 | 🔒 M3 真機驗收（8hr ≤ ~400MB） | M3 | — | ⬜ | 31–35 |
| **E. 本地推理 + L1/L2 敘事（rolling-wave）** ||||||
| 37 | 【展開】E 階段詳細 step 規劃 | M4 | Opus 4.8 | ⬜ | 36 |
| 38 | FoundationModels L1 Narrator 接線 | M4 | Opus 4.8 | ⬜ | 37 |
| 39 | Availability + fallback 階梯 | M4 | Opus 4.8 | ⬜ | 38 |
| 40 | L2 Summarizer | M4 | Sonnet 5 | ⬜ | 38 |
| 41 | sidecar `/vlm` 接 mlx-vlm | M4 | Opus 4.8 | ⬜ | 37 |
| 42 | 🔒 M4 真機驗收（本地 sub-second） | M4 | — | ⬜ | 38–41 |
| **F. 雲端 + 動作 + 接手互動（rolling-wave，第二高風險）** ||||||
| 43 | 【展開】F 階段詳細 step + 沙箱威脅模型 | M5 | Fable 5 | ⬜ | 42 |
| 44 | ContextEnvelope 打包邏輯 | M5 | Sonnet 5 | ⬜ | 43 |
| 45 | PII 出境閘門整合 | M5 | Opus 4.8 | ⬜ | 7,44 |
| 46 | LiteLLM Gateway 設定 + PIPL 路由 | M5 | Sonnet 5 | ⬜ | 43 |
| 47 | CloudRouter.handoff() 接 Claude computer-use | M5 | Fable 5 | ⬜ | 44,45,46 |
| 48 | 接手 HUD（推測任務/下一步/信心 + Approve/Skip/Stop） | 應用層 | Opus 4.8 | ⬜ | 43 |
| 49 | 熱鍵 ⌃⌥⌘Space → triggerIntervention 真接線 | 應用層 | Sonnet 5 | ⬜ | 9,47,48 |
| 50 | 風險分級 + 危險指令偵測 | M5 | Opus 4.8 | ⬜ | 43 |
| 51 | ActionExecutor 沙箱（XPC + sandbox-exec） | M5 | Fable 5 | ⬜ | 50 |
| 52 | Undo stack | M5 | Sonnet 5 | ⬜ | 51 |
| 53 | 🔒 M5 真機驗收（熱鍵後 Claude 正確接續 open loop） | M5 | — | ⬜ | 47,48,49,51,52 |
| **G. 隱私 + 黑名單（rolling-wave）** ||||||
| 54 | 【展開】G 階段詳細 step 規劃 | M6 | Opus 4.8 | ⬜ | 53 |
| 55 | tile 級遮罩（PII regex + AX secure field） | M6 | Opus 4.8 | ⬜ | 54 |
| 56 | SCContentFilter 黑名單 | M6 | Sonnet 5 | ⬜ | 54 |
| 57 | 熱圖隱私串接 | M6 | Sonnet 5 | ⬜ | 35,55 |
| 58 | 🔒 M6 真機驗收（PIPL 最終審查） | M6 | — | ⬜ | 55,56,57 |

---

## Phase A — 可跑骨架：操作時間機器

**階段目標**：幾週內產出第一個可在你 Mac 上實際開來用的 CoPartner——一個常駐 menu bar app，開啟觀察後把你的操作即時寫成 human-readable 劇本顯示出來（＝一台「操作時間機器」）。這一階段**只需 Input Monitoring + Accessibility 權限，不需 Screen Recording**，也不碰 Metal，因此絕大多數可用 CI 驗證，真機門檻最低。它同時提早打通全案最容易出錯的接縫：app 外殼 ↔ CoPartnerKit ↔ 全域熱鍵 ↔ 緊急停止。

#### Step 1 — CI 建置 app target（xcodegen + xcodebuild）✅
- **背景**：目前 `.github/workflows/ci.yml` 只 `swift build/test` 了 `packages/CoPartnerKit` 與 sidecar 的 ruff，**完全沒有建置 `apps/CoPartner/`**。那個 app 是 XcodeGen 專案（`project.yml`），是所有子系統唯一的組裝點——不建置就無法在 CI 抓到「app 連結不起來」。
- **修改檔案**：`.github/workflows/ci.yml`（新增步驟：`brew install xcodegen` → `cd apps/CoPartner && xcodegen generate` → `xcodebuild -project CoPartner.xcodeproj -scheme CoPartner build`）；視需要補 `apps/CoPartner/Sources/Info.plist`、`Sources/CoPartner.entitlements`（`project.yml` 有引用，若缺會建置失敗——順手補上）。
- **DoD**：✅ CI 綠燈（app 能被建置）。這步無新測試，但讓後續所有應用層 step 有 CI 守門。
- **建議模型**：Sonnet 5

#### Step 2 — AttentionModel 回歸測試 + 時鐘注入 ✅
- **背景**：`AttentionModel`（ADR-0006）已實作但**零測試**，且內部用 `Date()` 算衰減無法決定性測試。先做和 `EscalationPolicy.decide(_:now:)` 一致的 `now:` 參數注入（小重構），再補測試。
- **修改檔案**：`Sources/CaptureEngine/CaptureEngine.swift`（`update`/`captureParams`/`decay` 加 `now: Date = Date()`）；`packages/CoPartnerKit/Package.swift`（`CoPartnerKitTests` 依賴**加入 `"CaptureEngine"`**，目前沒有這條，測試會 import 失敗）。
- **新增測試**（`Tests/CoPartnerKitTests/AttentionModelTests.swift`）：`testClickSetsEnergyToPeakAndReturnsTrue`、`testIdleReturnsFalseAndDoesNotForceCapture`、`testHighSpeedMoveStaysBelowHotBand`、`testDragMaintainsAtLeast085Energy`、`testScrollMaintainsAtLeast06Energy`、`testEnergyDecaysAcrossHalfLife`（注入 `now` 前進 2s，斷言能量約減半）、`testEnergyBandThresholds`（0.7/0.4/0.15 邊界）、`testPointUpdatesCenter`。
- **DoD**：✅ CI 綠燈
- **建議模型**：Sonnet 5

#### Step 3 — CGEventTap → Signal 映射器（+ 🔒 真 tap 膠水）
- **目標**：把 `CGEventType`（`.leftMouseDown`/`.mouseMoved`/`.leftMouseDragged`/`.scrollWheel`/`.keyDown`）映射成 `AttentionModel.Signal`。膠水（`CGEvent.tapCreate`，需 Input Monitoring）與映射邏輯分開。
- **新增檔案**：`Sources/CaptureEngine/EventTapMapper.swift`（純函式 `func signal(for:mouseDelta:) -> AttentionModel.Signal?`）+ 🔒 `Sources/CaptureEngine/InputEventTap.swift`（真 tap，含 `kCGEventTapDisabledByTimeout` 處理）。
- **新增測試**（`EventTapMapperTests.swift`）：每個 `CGEventType` 對應正確 `Signal`；未知類型回 `nil`；快速移動 `speed` 映射較低能量。
- **DoD**：mapper ✅ CI 綠燈；tap 🔒（隨 Step 10 真機驗）
- **建議模型**：Sonnet 5

#### Step 4 — AX 焦點區域解析（+ 🔒 真 AX 膠水）
- **目標**：§B.4 焦點元件定義重點區域。抽 `protocol AXFocusProviding`（回傳 focused element 的 role/value/frame），純邏輯算焦點區 `CGRect` 與「打字時錨定 focused element 而非游標」的判斷。
- **新增檔案**：`Sources/CaptureEngine/FocusRegionResolver.swift` + 🔒 `Sources/CaptureEngine/SystemAXFocusProvider.swift`（`AXUIElementCreateSystemWide` + `kAXFocusedUIElementAttribute` + `AXObserver`）。
- **新增測試**（`FocusRegionResolverTests.swift`）：假 provider 給不同 AXFrame → 驗證區域計算；無焦點時的 fallback。
- **DoD**：✅ CI 綠燈（假 provider）；真 AX 🔒
- **建議模型**：Sonnet 5

#### Step 5 — L0 事件模板格式化器 ✅
- **目標**：依 `docs/design/v2.1_action-script-narrator.md §2` 行格式（`[HH:mm:ss.SSS] FOCUS app=... win=...` 等）寫格式化器。`ScriptNarrator.swift` 已有 `EventLog` 骨架（只有 `append`）。
- **新增檔案**：`Sources/ScriptNarrator/EventFormatter.swift`；`Package.swift` 測試依賴已含 `ScriptNarrator`（免改）。
- **新增測試**（`EventFormatterTests.swift`）：6 種事件（FOCUS/TYPE/PASTE/SWITCH/SCROLL/WATCH）格式正確；時間戳精度到毫秒。
- **DoD**：✅ CI 綠燈
- **建議模型**：Sonnet 5

#### Step 6 — L0 合併規則（打字合併 / scroll 節流）✅
- **目標**：同欄位 2s 內文字輸入合併成一句；scroll 1s 視窗聚合方向+距離。用注入 `now:` clock 做決定性測試。
- **修改檔案**：`Sources/ScriptNarrator/ScriptNarrator.swift`（`EventLog.append` 擴充合併邏輯）。
- **新增測試**（`EventLogMergeTests.swift`）：連續打字合併成一行；跨欄位不合併；scroll 節流；超過視窗不合併。
- **DoD**：✅ CI 綠燈
- **建議模型**：Sonnet 5

#### Step 7 — L0 PII 遮罩（貼上/剪下前置遮罩）✅
- **目標**：套 `docs/privacy/data-classification.md` regex（TW 身分證 `[A-Z][12]\d{8}`、TW 手機 `09\d{8}`、CN 身分證 `\b\d{17}[\dXx]\b`）在**進入 L0 之前**遮罩貼上/剪下，如 `[貼上疑似卡號，已遮罩]`。
- **新增檔案**：`Sources/ScriptNarrator/PIIMasker.swift`。
- **新增測試**（`PIIMaskerTests.swift`）：各 PII pattern 必遮；非 PII 不誤傷；preview 截斷長度正確；密碼欄輸入標 `[在密碼欄輸入]`。
- **DoD**：✅ CI 綠燈
- **建議模型**：**Opus 4.8**（隱私關鍵，漏遮＝PII 進劇本）

#### Step 8 — 即時事件日誌 view-model + 接進 menu bar
- **目標**：把 Step 3/4/5/6/7 串成一條 pipeline，餵給一個可觀察的 view-model；`AppCoordinator.toggleObserving()` 真的啟動/停止這條 pipeline；menu bar 新增一個視窗即時顯示最近 L0 劇本行。這就是「操作時間機器」的畫面。
- **修改/新增檔案**：`apps/CoPartner/Sources/AppCoordinator.swift`（`toggleObserving` 真接線；`lastStepSummary` 改由 pipeline 更新）、新增 `apps/CoPartner/Sources/EventLogViewModel.swift` + `EventLogWindow.swift`。**把可測邏輯放進 CoPartnerKit**（新增 `Sources/ScriptNarrator/EventLogFeed.swift`：ring buffer + 對外 `AsyncStream`），app 只做顯示。
- **新增測試**（`EventLogFeedTests.swift`）：餵事件序列 → feed 吐出對應格式化行；容量上限；停止後不再吐。
- **DoD**：`EventLogFeed` 邏輯 ✅ CI 綠燈；SwiftUI 視窗實際顯示 🔒（隨 Step 10）
- **建議模型**：Sonnet 5

#### Step 9 — 緊急停止（⌃⌥⌘.）+ 觀察開關（⌃⌥⌘O）真接線
- **目標**：接上 `KeyboardShortcuts`（目前宣告了卻無 target 使用）。⌃⌥⌘O 切換觀察、⌃⌥⌘. **立即停止所有 pipeline 並回 idle**（kill-switch，安全關鍵）。menu bar 圖示反映 `mode`（eye.slash/eye/wand）。這是常駐工具「信任感」與安全的基石。
- **修改檔案**：`Package.swift`（新增一個小 target 或讓 app 依賴 `KeyboardShortcuts`——因熱鍵屬 app 層，建議在 `apps/CoPartner` 的 `project.yml` 加 `KeyboardShortcuts` package 依賴，而非塞進函式庫）；`AppCoordinator.swift`（`stopAll()` 冪等停止）；`MenuBarContentView.swift`（緊急停止鈕已存在，接真行為）。
- **新增測試**（`AppCoordinatorTests.swift`，放 app 的測試 target 或抽邏輯進 kit）：`stopAll()` 從任一 mode 都回 idle 且冪等；observe toggle 狀態機正確。
- **DoD**：狀態機邏輯 ✅ CI 綠燈；全域熱鍵實際觸發 🔒
- **建議模型**：**Opus 4.8**（kill-switch 是「接手你電腦的工具」最重要的安全控制，停止路徑要一次對）

#### Step 10 — ✅ 可跑骨架 dogfood 驗收（操作時間機器）— 真機通過（2026-07-03）
- **結果**：在真機（非標準鍵盤的 Mac mini）上通過。眼睛圖示、開始觀察、FOCUS/SWITCH（免權限）皆正常；授權輸入監控+輔助使用後 TYPE（合併成詞）/ SCROLL 皆正確；**假卡號→`[貼上疑似卡號，已遮罩]`、密碼欄不外洩實際字元的隱私遮罩在真機生效**（Phase A 最關鍵驗證）；CPU ~5%（純事件追蹤，尚無螢幕擷取）；無 crash。
- **發現**：固定熱鍵 ⌃⌥⌘. / ⌃⌥⌘O 在非標準鍵盤上不好按 → 需可設定熱鍵（Step 10.5）。
- **對應 roadmap 驗收**：M2.5「劇本完整重現一段操作（時間機器）」✅。

#### Step 10.5 — 使用者可設定熱鍵（KeyboardShortcuts.Recorder 設定視窗）
- **背景**：dogfood 發現固定熱鍵不通用（非標準鍵盤）。`KeyboardShortcuts` 內建 Recorder UI，讓使用者自錄熱鍵並自動持久化（UserDefaults），不需自造。
- **修改/新增檔案**：新增 `apps/CoPartner/Sources/SettingsView.swift`（兩個 `KeyboardShortcuts.Recorder(for: .toggleObserve)` / `.emergencyStop`）；`CoPartnerApp.swift` 加 `Settings { SettingsView() }` scene（⌘, 開啟）；`MenuBarContentView` 加「設定…」按鈕（`SettingsLink` 或 `NSApp.sendAction(Selector(("showSettingsWindow:")))`）。預設值沿用 step 9 的 ⌃⌥⌘O / ⌃⌥⌘.，使用者可覆蓋。
- **DoD**：主要為 🔒 app 膠水（KeyboardShortcuts 自理持久化，純邏輯近乎為零）——app job 編譯 ✅ + 真機驗收「改了熱鍵會生效且重開仍記得」。
- **建議模型**：Sonnet 5（標準 SwiftUI + 既有庫）

---

## Phase B — 智慧擷取引擎

**階段目標**：把螢幕視覺擷取（foveated / dirty-region / tile）疊到「已經會跑」的事件日誌上。延續 `docs/design/v2_smart-capture-engine.md §B`，採 §M 的 **Tier 2 簡化路徑**先驗證收益（Step 11–18＝原 M0），再做完整 tile 狀態機（Step 19–24＝原 M1）。這一階段真機依賴最重（SCStream/Metal/Screen Recording 權限），也是我最幫不上手動除錯的地方——所以邏輯全抽出來測，膠水獨立薄層。

#### Step 11 — Tile 座標與幾何工具 ✅
- **新增檔案**：`Sources/CaptureEngine/TileGrid.swift`（`tileSize`(128)/`cols`/`rows`、`tileIndex(for:)`、`tiles(overlapping:)`、`rect(forTileX:y:)`）。
- **新增測試**（`TileGridTests.swift`）：`testTileIndexAtOrigin`、`testTileIndexAtExactBoundary`、`testTilesOverlappingRectSpanningMultipleTiles`、`testTilesOverlappingRectClampsToGridBounds`、`testRectForTileRoundTrip`。
- **DoD**：✅ CI 綠燈 ・ **模型**：Sonnet 5

#### Step 12 — Metal dHash 差異比對邏輯 + 🔒 shader 骨架
- **交付（✅ 完成，Fable 5 全步執行）**：`TileHashDiff.swift`（hammingDistance / ChangeMagnitude{none,small,large} / ChangeThresholds smallMaxBits=2，8 測試）+ `Resources/TileHash.metal`（9×8 亮度格 dHash；一 threadgroup 一 tile、單 writer 零 atomics；防 uint underflow 與 divergent barrier）+ `TileHashComputer.swift`（🔒 host dispatcher，dispatch 契約以代碼固定）。
- **實作發現**：(1) SPM/Xcode 會自動編譯 target 內 `.metal` → **CI 其實能把關 shader 語法/型別**，比原估「完全驗不到」好；真機只剩 hash 正確性+效能（step 18）。(2) `Bundle.module` 需 Package.swift 宣告 `resources:[.process("Resources")]` 才會合成——純 swift build 首推曾紅一次，已修（cbb83a7）。
- **DoD**：Swift + `.metal` 編譯 ✅ CI；hash 正確性/效能 🔒（Step 18 驗）

#### Step 13 — SCStream dirtyRects 解析與可靠性防禦
- **目標**：對抗 §B.1 已知陷阱（status 常回 idle、dirtyRects 可能空、Sequoia 15.6.1 contentRect X=48 bug）。protocol 抽象 SCK，Metal hash 永遠當 ground truth。
- **新增檔案**：`Sources/CaptureEngine/DirtyRegionResolver.swift`（`protocol FrameInfoProviding`、`enum FrameStatus`、`struct DirtyRegionResolver`）+ 🔒 `Sources/CaptureEngine/ScreenCaptureSource.swift`（真 `SCStream` adapter）。
- **新增測試**（`DirtyRegionResolverTests.swift`）：`testDirtyRectsMapToCorrectTiles`、`testIdleStatusFallsBackToHashDiff`（status=idle 但 hash 有差 → 仍報變動）、`testEmptyRectsUnchangedHashesReportsNoChange`、`testEmptyRectsButHashChangedStillReportsChange`、`testMultipleRectsAggregate`。
- **DoD**：resolver ✅ CI（假 provider）；`ScreenCaptureSource` 🔒 ・ **模型**：**Opus 4.8**（全 B 階最易藏 bug——對抗平台陷阱）

#### Step 14 — ScreenCaptureSource 膠水 + CaptureEngine 串接
- **目標**：把 `AttentionModel`+`TileGrid`+`DirtyRegionResolver` 接進 `CaptureEngine` actor，`start()` 產生 `AsyncStream<TileEvent>`，`stop()` 停止。
- **修改檔案**：`Sources/CaptureEngine/CaptureEngine.swift`。
- **新增測試**（`CaptureEngineTests.swift`）：假 frame 來源驅動 `start()` → 斷言吐出的 `TileEvent` 正確；`stop()` 後不再吐。
- **DoD**：✅ CI（假來源）；真 `ScreenCaptureSource` 🔒 ・ **模型**：Sonnet 5

#### Step 15 — 多解析度金字塔參數 ✅
- **目標**：§B.5 三層（L0 焦點 2x / L1 周邊 1x-0.5x / L2 概覽 ≤1024px）參數化（`struct CapturePyramid` 或擴充 `captureParams()`）。
- **新增測試**：各能量帶 → 正確三層參數。**DoD**：✅ CI ・ **模型**：Sonnet 5

#### Step 16 — 擷取接進 app（視覺脈絡疊加事件日誌）
- **目標**：`toggleObserving()` 除了事件日誌，也啟動 `CaptureEngine`；menu bar 反映擷取狀態。Screen Recording 權限在此才需要。
- **DoD**：協調邏輯 ✅ CI；真擷取顯示 🔒 ・ **模型**：Sonnet 5

#### Step 17 — 量測 harness（CPU/延遲/漏抓率）
- **目標**：可在真機執行的量測工具（CLI 或 debug flag），dump CPU%/每幀延遲/tile 變動計數，供 Step 18 產數字。
- **DoD**：工具碼 ✅ CI 可編譯；量測結果 🔒 ・ **模型**：Sonnet 5

#### Step 18 — 🔒 M0 真機驗收
- 打包簽章 app（`scripts/permissions-check.sh` 先跑）、授權三權限、跑 harness，量 CPU%/漏抓率/延遲，產 V1 vs V2 對照數字（roadmap M0 驗收）。你在 Mac 上執行、回報。

#### Step 19 — Tile 狀態機（COLD/WARM/HOT/DYNAMIC）
- **目標**：純狀態轉換（吃 Step 12 的 `ChangeMagnitude` 時間序列）→ `TileEvent.State`，規則見 §B.6。
- **測試重點**：COLD 維持；單次變化→WARM；持續→HOT；規律高頻大面積→DYNAMIC；**AX 可得文字的 tile 不套 DYNAMIC**（§L override）。
- **DoD**：✅ CI ・ **模型**：Sonnet 5 實作，**Opus 4.8** 審 DYNAMIC 誤判閾值

#### Step 20 — DYNAMIC 週期性偵測
- 偵測變動時間戳是否規律（30/60fps 倍數），合成時間序列可測。**DoD**：✅ CI ・ **模型**：Opus 4.8

#### Step 21 — 每 app override 清單
- §L：允許 per-app 排除 DYNAMIC 判定（股價 ticker 等）。**DoD**：✅ CI ・ **模型**：Sonnet 5

#### Step 22 — OCR/持久化節流串接
- 狀態機輸出 → 「該不該 OCR / 存 delta」節流（§B.6 表），假 spy 驗呼叫次數。**DoD**：✅ CI ・ **模型**：Sonnet 5

#### Step 23 — CaptureEngine 全狀態機整合
- 把 Tier 2 換成完整 per-tile 狀態機驅動頻率/解析度。**DoD**：✅ CI（假來源）；真機 🔒 ・ **模型**：Sonnet 5

#### Step 24 — 🔒 M1 真機驗收
- 播 1080p 影片 CPU 不超 baseline；影片正確標 DYNAMIC。你在 Mac 上執行、回報。

---

## Phase C — 局部 OCR + AX 文字

延續 §B.8。（原 M2.5 的 L0 已在 Phase A 完成。）

#### Step 25 — Vision OCR ROI 映射器（+ 🔒 真 OCR）
- 可測：dirty tiles → normalized ROI rect。新增 `Sources/CaptureEngine/OCRRegionMapper.swift` + 🔒 真 `VNRecognizeTextRequest`（`.accurate`、zh-Hant+en）。**DoD**：ROI ✅ CI；辨識品質 🔒 ・ **模型**：Sonnet 5

#### Step 26 — AX-text-first fallback 邏輯
- 「能拿 AX 文字的 tile 不跑 OCR」決策，假 AX text provider 測。**DoD**：✅ CI ・ **模型**：Sonnet 5

#### Step 27 — sidecar `/ocr` 接線（ocrmac）
- 把 `sidecar/.../server.py` 已 stub 的 `/ocr` 接上 `ocrmac`。**DoD**：邏輯待 Step 28 pytest 驗；辨識品質 🔒 ・ **模型**：Sonnet 5

#### Step 28 — CI 補 Python pytest job ✅
- **背景**：CI 的 `python` job **只有 `ruff check`，沒有測試**。補上。
- **修改檔案**：`sidecar/pyproject.toml`（加 `pytest` dev dep）、新增 `sidecar/tests/`、`.github/workflows/ci.yml`（加 `uvx pytest`）。**DoD**：✅ CI ・ **模型**：Sonnet 5

#### Step 29 — 🔒 M2 真機驗收
- OCR 像素吞吐 ≤ V1 的 20%。你在 Mac 上執行、回報。

---

## Phase D — 記憶系統（rolling-wave）

延續 §C + v2.1 §3（劇本＝檢索主幹）。`MemoryStore.swift` 已有 `insert`/`search` 空殼。

- **Step 30 【展開】**：依 Phase A/B 真機結果（尤其 tile hash 實際資料量）把 D 階 step 展開成完整測試案例清單。**模型**：Opus 4.8
- **Step 31 Reference+delta 重建**：I/P-frame（§B.7），**資料正確性風險最高**（重建錯＝靜默損毀）。**模型**：Sonnet 5 實作 + **Opus 4.8 審查**
- **Step 32 L1 RAM ring buffer**：最近 5–15 min 熱劇本。**模型**：Sonnet 5
- **Step 33 sqlite-vec schema + KNN**：`vec0` float[768] + `MemoryStore.insert/search` 實作；extension 載入 🔒，query/ranking 可測；`Package.swift` 測試依賴**加入 `"MemoryStore"`**。**模型**：Opus 4.8
- **Step 34 Re-baseline 觸發**：每 T 秒或 delta > 畫面 X% → re-baseline。**模型**：Sonnet 5
- **Step 35 注意力熱圖**：衰減式 heatmap，只存聚合權重（§G：不存原始座標時序）。**模型**：Sonnet 5
- **Step 36 🔒 M3 真機驗收**：8hr 磁碟 ≤ ~400MB；語意檢索可用。

---

## Phase E — 本地推理 + L1/L2 敘事（rolling-wave）

`Narrator.narrate()` 目前回固定 `nil`，這裡真正接上。

- **Step 37 【展開】**。**模型**：Opus 4.8
- **Step 38 FoundationModels L1 Narrator**：接 `LanguageModelSession` + `@Generable ActionStep` + `prewarm()`（v2.1 §2 有完整程式碼可改寫）。**模型**：Opus 4.8
- **Step 39 Availability + fallback 階梯**：FoundationModels 不可用 → Qwen MLX → 規則模板（§5）；假 availability 狀態驗證選對路徑。**模型**：Opus 4.8
- **Step 40 L2 Summarizer**：切 app / 數分鐘 rollup。**模型**：Sonnet 5
- **Step 41 sidecar `/vlm` 接 mlx-vlm**：載入 `Qwen2.5-VL-7B-Instruct-4bit` generate。**模型**：Opus 4.8
- **Step 42 🔒 M4 真機驗收**：本地路徑 sub-second；L1 意圖準確率；FoundationModels 實際 availability（只有真機能驗）。

---

## Phase F — 雲端 + 動作 + 接手互動（rolling-wave，第二高風險）

這是**「下達接手命令」的完整體驗**所在：把劇本交給 Claude、顯示接手 HUD、熱鍵觸發、沙箱執行。`CloudRouter.handoff()`、`ActionExecutor.execute()` 目前是空殼。

- **Step 43 【展開】+ 沙箱威脅模型**：全案風險第二高（AI 發指令、sandbox 執行）；展開前先寫沙箱威脅模型草稿。**模型**：**Fable 5**
- **Step 44 ContextEnvelope 打包**：v2.1 §4.1 有完整 JSON 範例（劇本主體 + 焦點小圖 + AX + 剪貼簿 + takeover contract）。**模型**：Sonnet 5
- **Step 45 PII 出境閘門整合**：Presidio + 分類表，出境前最後檢查（接 Step 7 遮罩）。**模型**：Opus 4.8
- **Step 46 LiteLLM Gateway 設定 + PIPL 路由**：`infra/litellm/config.yaml` 已有雛形（cost-based routing、presidio、$5/day 熔斷）；補 PIPL guard（含上海個資 → local-only 強制不出境）。**註**：config 內雲端模型 id（目前 `claude-sonnet-4-6`/`claude-opus-4-7`）指的是「執行 computer-use 的雲端模型」，開工時對齊當時 computer-use 支援清單。**模型**：Sonnet 5
- **Step 47 CloudRouter.handoff() 接 Claude computer-use**：beta header `computer-use-2025-11-24`、tool `computer_20251124`、Retina 座標 ÷2、prompt caching 穩定前綴。**模型**：**Fable 5**
- **Step 48 接手 HUD（Approve/Skip/Stop）**：design §F 的介入 HUD——顯示推測任務 + 下一步 + 信心度 + Approve/Skip/Stop 的**常駐浮層**（非 menu）。這是使用者「看到 AI 接手」的畫面。HUD 狀態邏輯（該顯示什麼、按鈕導致什麼狀態轉換）抽進可測 view-model。**模型**：Opus 4.8（人在迴圈的確認 UX，攸關安全與信任）
- **Step 49 熱鍵 ⌃⌥⌘Space → triggerIntervention 真接線**：把 `AppCoordinator.triggerIntervention()` 接上「打包 ContextEnvelope → PII 閘門 → CloudRouter.handoff → 顯示 HUD」。**修正 `AppCoordinator.swift` 內 `TODO(M3)` 的錯誤標記**（熱鍵交棒屬 M5/此 step，非 M3 記憶系統）。建於 Step 9 的 KeyboardShortcuts 基礎上。**模型**：Sonnet 5
- **Step 50 風險分級 + 危險指令偵測**：`rm -rf`/`sudo`/`git push -f`/`dd`/`curl|sh` pattern → 強制 confirm-each，純 pattern 可測。**模型**：Opus 4.8
- **Step 51 ActionExecutor 沙箱（XPC + sandbox-exec）**：`_ambient` unprivileged user + sbpl profile（限 network/exec/file write）；`Package.swift` 測試依賴**加入 `"ActionExecutor"`**。**模型**：**Fable 5**（安全邊界錯＝真漏洞）
- **Step 52 Undo stack**：git stash / APFS snapshot / AX tree snapshot。**模型**：Sonnet 5
- **Step 53 🔒 M5 真機驗收**：不貼說明，熱鍵後 Claude 正確接續 open loop；高風險動作強制確認；⌃⌥⌘. 能中止接手。

---

## Phase G — 隱私 + 黑名單（rolling-wave）

- **Step 54 【展開】**。**模型**：Opus 4.8
- **Step 55 tile 級遮罩**：`kAXSecureTextField` + URL/標題啟發式 + OCR 正則（卡號/身分證/API key）。**模型**：Opus 4.8（漏遮＝PII 外洩）
- **Step 56 SCContentFilter 黑名單**：白名單 `includingApplications`（避空陣列 bug）、排除自身 app（避錄製迴圈）。**模型**：Sonnet 5
- **Step 57 熱圖隱私串接**：串 Step 35 熱圖與遮罩，確保聚合權重也不洩漏敏感區。**模型**：Sonnet 5
- **Step 58 🔒 M6 真機驗收（PIPL 最終審查）**：密碼欄/銀行頁 100% 被遮；黑名單 app 0 frame；全案跑一輪隱私稽核。

---

## 完成後 = 你描述的成品

58 步做完，對照你的大目標：

- **「開啟後持續理解操作習慣」** → Phase A（操作時間機器，開著就在記）+ Phase C/D/E（OCR/記憶/L1-L2 敘事把「記錄」升級成「理解」）。
- **「下達接手命令就接手」** → Phase F（熱鍵/語音*→ 接手 HUD → Claude computer-use → 沙箱執行 → 可中止）。
- **「依難易度調用本地/雲端」** → 已由 ADR-0007 `EscalationPolicy` 落地，Phase B/E 產生它需要的訊號，Phase F 執行雲端那一端。

## 本輪之後 → 版本演化總規劃

V1（本文件的 58 步）之後的完整版本階梯已展開為獨立規劃：**`docs/planning/assistant-evolution-plan.md`**——
**V2 Listen**（全日音訊→生活劇本 + Telegram 訊息閘道 + 語音交棒；原本此處「V3 展望」的語音項目全數併入 V2）→
**V3 Agent**（TopAppSkills 技能引擎 + heartbeat 主動性 + 手機/手錶衛星 + 信任階梯）→
**V4 Omni**（穿戴優先的最終全能助理形態）。該文件同樣採 step-by-step TDD 方法論，可用「完成 V2 step N」交辦。
其餘候選（App Store / Developer ID 分發、團隊協作）視 V2 後需求再排。

現在可以說「**完成 step 1**」開始（step 1＝讓 CI 真的建置 app，替後面的可跑骨架架好安全網）。
