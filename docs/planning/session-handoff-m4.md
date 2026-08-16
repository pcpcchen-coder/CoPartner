# Session 交接 — 從 M2 完成到 M4 開工

> **上一個 session**：https://claude.ai/code/session_01ALsaZzaC9nMLDPG9uRCyXT
> （全案 58 步 backlog 從零建起 → PR #1/#2/#3 合併 → M2 真機驗收通過 → M4 探針推出）
> 需要查完整討論脈絡（為什麼這樣設計、踩過哪些坑）可回上面連結。
> 本文件是**可獨立運作的交接包**：只看這份 + repo 就能無縫接續。

---

## 1. 這個專案是什麼

**CoPartner** — macOS 常駐 menu bar 的 ambient AI 助理。開著就持續把使用者的操作寫成
human-readable 的「操作劇本」，理解在做什麼；按熱鍵可交棒給雲端 Claude 接手續做。
依任務難易度在本地/雲端之間路由（ADR-0007）。

**核心設計文件**（動手前該讀的）：
- `docs/planning/implementation-backlog.md` — 58 步 TDD backlog，**進度的單一事實來源**
- `docs/planning/realmachine-runbook.md` — 🔒 真機里程碑逐步 dogfood 清單
- `docs/design/sandbox-threat-model.md` — Phase F 安全設計（不變式 I1–I10）
- `docs/design/v2_smart-capture-engine.md`、`v2.1_action-script-narrator.md` — 主設計

---

## 2. 現在在哪裡

### 已完成（CI 綠 + 已合併進 main）
Phase A–G 的**CI 可測部分全部完成**（backlog step 1–57，扣延後的 23.5）。
三個 PR 皆已合併：#1 全案骨架、#2 M2 OCR 接線、#3 OCR 改 Vision。

### 真機里程碑戰績
| 里程碑 | 狀態 |
|---|---|
| Phase A 操作時間機器（step 10）| ✅ 真機通過 |
| **M2 局部 OCR（step 29）** | ✅ 真機通過，吞吐 **18%**（目標 ≤20%）|
| M1 影片 DYNAMIC + CPU（step 24）| 🔒 待做（前置 23.5 CPU 優化）|
| M3 記憶真 vec0（step 36）| 🔒 待做 |
| **M4 本地敘事（step 42）** | 🔒 **← 正在做，見 §3** |
| M5 接手（step 53）| 🔒 待做 |
| M6 隱私最終審查（step 58）| 🔒 待做 |

---

## 3. ⏭️ 立即要做的事：M4 探針校準

### 狀態
探針已寫好並推送（commit `1b49a6e`）：
`packages/CoPartnerKit/Sources/ScriptNarrator/FoundationModelsProbe.swift`

**正在等使用者在 macOS 26 的 Xcode 按 ⌘B，回報編譯錯誤。**

### 為什麼要探針（重要脈絡）
`FoundationModelsNarrator.swift` 用到 **7 個從未被編譯過的 API 面**，而 **CI 永遠驗不到**——
macos-15 runner 沒有 FoundationModels 框架 → `canImport` 為 false → 整檔略過。
**只有使用者的 macOS 26 機器能當編譯器。**

一次編譯整個 narrator 會噴互相牽連的錯誤、難判根因，所以先用逐項隔離的編號探針
（PROBE 1–7）一輪校準所有簽章：

| PROBE | 驗什麼 |
|---|---|
| 1 | `@Generable` / `@Guide` 巨集能否套用在 struct 與 String/Double/Bool/[String] 欄位 |
| 2 | `SystemLanguageModel.default` 存不存在 |
| 3 | `.availability` 的型別與 `.available` case 名稱 |
| 4 | `LanguageModelSession()` 與 `LanguageModelSession(instructions:)` 兩種建構式 |
| 5 | `prewarm()` 是否同步、無參數、非 throwing |
| 6 | `respond(to:generating:)` 的 async/throws、泛型位置、回傳值有無 `.content` |
| 7 | 純文字 `respond(to:)` 的回傳型別 |

### 收到編譯錯誤後怎麼做
1. 依錯誤修正 `FoundationModelsProbe.swift` 與 `FoundationModelsNarrator.swift` 的簽章
2. 請使用者再 ⌘B 確認（可能 1–3 輪）
3. 簽章校準完成 → 寫**完整接線**（見下）
4. 探針可刪，或留作 API 契約的可執行文件

### 校準後的 M4 完整接線（尚未做）
- `AppCoordinator`：L0 劇本行 → `NarrationLadder`（已 CI 綠）→ L1 `ActionStep`
  → 選單顯示「一句話 step + 推測目標」+ 存進 `L1HotBuffer` / `MemoryStore`
- 目前 `triggerIntervention` 的 `steps: []` 是佔位（`AppCoordinator.swift` 約 116 行），
  接線後要餵真 L1 steps
- 驗收標準（`realmachine-runbook.md` M4 節）：L1 rollup < ~300ms、prewarm 生效、
  availability 偵測正確、關閉 Apple Intelligence 時 fallback 到規則式不中斷

---

## 4. 工作方式（這個專案的節奏）

**核心約束**：開發代理跑在 Linux 容器，**無 Mac / GPU / 螢幕 / 權限 / Apple Intelligence**。
所以平台膠水一律「盲寫」，真行為只能靠使用者 dogfood。

```
我寫膠水（CI 可測部分寫測試）→ push → CI 三 job 綠
  → 使用者 git pull + ./scripts/bootstrap.sh + Xcode ⌘R
  → 使用者回報（截圖/錯誤/數字）→ 我修 → 標記里程碑 ✅
```

**貫穿全案的兩個工程原則**（維持它們）：
1. **可注入後端 + 誠實佔位**：平台重活（Metal/SCK/vec0/FoundationModels/computer-use/XPC）
   藏在 protocol 後，CI 用假後端驗邏輯；真後端標 🔒，佔位一律 `throw` 而非靜默假成功
   （例：`SQLiteVecIndex.notWired`、`ActionExecutor.notWired`）
2. **安全不變式寫進型別**：`ApprovalToken` 的 `internal` init 讓「繞過確認閘門」在編譯層面
   不存在；`ProposedAction` 無整串 shell 欄位（只有 argv）；黑名單空清單回 `nil` 非空陣列

**Git 慣例**：
- 分支 `claude/loving-darwin-Ka636`，一步一 commit，批次做完開 PR
- commit trailer：`Co-Authored-By: Claude <型號> <noreply@anthropic.com>` + `Claude-Session: <url>`
- CI 三 job（macos-15）：`swift`（build+test）/ `python`（ruff+pytest）/ `app`（xcodegen+xcodebuild）
- **PR 合併後**若要繼續開發，從最新 `main` 重開分支，不疊在已合併歷史上

---

## 5. 真機環境注意事項（踩過的坑）

| 坑 | 解法 |
|---|---|
| **TCC 授權反覆失效**：未簽章開發版每次 rebuild 身分就變，清單顯示已開卻一直索權 | `tccutil reset ScreenCapture com.pcpcchen.copartner.CoPartner` → 重新授權 → **停止再重跑**（授權對新程序才生效）。根治：Xcode → Signing & Capabilities → Team 選固定帳號（免費個人帳號即可） |
| **有新檔一定要 `./scripts/bootstrap.sh`** | 否則 xcodegen 沒把新檔加進專案，Xcode 找不到 |
| **sidecar** | OCR 已改用 macOS Vision，**日常使用不需要 sidecar**。sidecar 只留給 `/vlm`（Qwen2.5-VL/MLX），且 M4 應改為**按需啟動**——使用者不該自己開終端機跑服務（這是使用者明確提出的產品要求） |
| sidecar 啟動（若 M4 要驗 `/vlm`）| `cd sidecar && uv sync && uv run copartner-sidecar` |
| **Xcode console 的 `com.apple.linkd.autoShortcut` 紅字** | 無害系統雜訊（App Intents 註冊），CoPartner 沒用到，忽略 |
| CoPartner 是 **menu bar app**（`LSUIElement: true`）| 沒有視窗/Dock 圖示，從右上角眼睛圖示操作 |

---

## 6. 真機 dogfood 抓到過的 bug（CI 都測不到的那種）

作為「什麼樣的 bug 只有真機會現形」的參考：

1. **FOCUS 狂刷**（M2）— `pollFocus` 誤用 AX `value`（欄位內容）當視窗識別，終端機每輸出
   一字就被判定換視窗 → 同秒噴十幾行。修：改用 `windowTitle`（沿 AXParent 找 AXWindow 讀
   AXTitle）+ 滑鼠 move 不輪詢焦點。`FocusIdentityRegressionTests` 釘住。
   **教訓**：tracker 邏輯本身正確、測試也過——錯在真機餵給它的資料。
2. **OCR 截整螢幕**（M2）— 混入選單列/他 app 文字且等同 V1 吞吐。修：`OCRCropPlanner`
   依 AX 焦點框裁切。
3. **Vision bbox 左下原點**（M2）— 與螢幕座標慣例相反，沿用會讓摘要上下顛倒。
   修：`OCRTextDigest.BBoxOrigin` 要求呼叫端明講慣例。
4. **`uv run copartner-sidecar` spawn 失敗** — `pyproject.toml` 缺 `[build-system]`，
   uv 視為 non-package 專案不安裝 script。修：補 hatchling backend。

---

## 7. 之後的路線

M4 完成後可選：
- **M3 記憶真 vec0**（step 36）— 盲寫風險低（sqlite-vec C API 穩定），但要裝 sqlite-vec + 跑 8hr 驗磁碟量
- **M5 接手**（step 53）— 頭號功能，膠水最多。⚠️ **開工第一件事**：用 `/claude-api` skill
  對齊 live computer-use 契約（`HandoffRequestBuilder` 的 `betaHeader`/`toolType` 預設值是
  開發時 docs 連不上暫定的，很可能過時），再接真 transport + XPC executor + sandbox-exec
- **M1 影片 CPU**（step 24）— 前置 step 23.5 擷取 CPU 優化（只 hash dirty tile + async GPU
  + 自適應幀率），建議配 Instruments 抓真熱點
- **M6 隱私最終審查**（step 58）

以及使用者提出但尚未做的產品需求：**sidecar 打包/託管**（app 自己 spawn 子程序、
結束時收掉、健康檢查重啟），讓 `/vlm` 也不需使用者手動啟動。
