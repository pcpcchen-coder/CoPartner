# Session 交接包

> **這份文件是什麼**：只看這份 + repo 就能無縫接續開發的交接包。
> 標題原為「從 M2 完成到 M4 開工」，但內容早已涵蓋 M4 完成與 M5 大半——
> 改成不綁里程碑的名字，免得每過一個里程碑就名不副實。
>
> **導讀**：§4 是工作方式（先讀）、§7 是當前待辦、§7.6 是最近一次自我審查的結論。
> §3 保留 M4 的完整過程作為方法論參考，不必先讀。
> 架構圖見 [`docs/architecture/`](../architecture/overview.md)（Mermaid，可直接編輯）。

> | | Session |
> |---|---|
> | **上一個**（建全案骨架 → M2 驗收）| https://claude.ai/code/session_01ALsaZzaC9nMLDPG9uRCyXT |
> | **接續**（M4 本地敘事）| https://claude.ai/code/session_01CmetxvBBBY35hD9aMNjZds |
>
> 上一個 session 涵蓋：全案 58 步 backlog 從零建起 → PR #1/#2/#3 合併 → M2 真機驗收通過
> → M4 探針推出。需要查完整討論脈絡（為什麼這樣設計、踩過哪些坑、使用者偏好）可回去看。
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
| **M4 本地敘事（step 42）** | ✅ **真機通過**，延遲 1373–2388ms、fallback 驗證通過（`/vlm` 延後）|
| **M5 接手（step 53–54）** | 🔒 **← 正在做**：契約 ✅、假 SSE ✅、HUD ✅ 真機通過；剩真執行端，見 §7 |
| M6 隱私最終審查（step 58）| 🔒 待做 |

---

## 3. M4 本地敘事 ✅ 已完成（2026-08-16 真機驗收通過）

> 本節保留 M4 的完整過程作為方法論參考。**當前待辦是 M5，見 §7。**

### 3.1 探針校準 ✅ 已完成
探針（commit `1b49a6e`）：`packages/CoPartnerKit/Sources/ScriptNarrator/FoundationModelsProbe.swift`

**結果：7 項簽章一次全過、零紅字**，`FoundationModelsNarrator` 無需任何修改。
原本預估 1–3 輪校準，實際 0 輪——盲寫的 API 面完全命中。

⚠️ **但第一輪 build 成功不等於驗證成功**：`canImport` 為 false 時整檔靜默略過、
build 照樣綠，「編譯通過」與「根本沒編譯」在結果上完全無法分辨。於 `#if` / `#else`
兩側各放一個 `#warning` 取得編譯期證據，看到黃字「PROBE ACTIVE」掛在
ScriptNarrator → FoundationModelsProbe.swift 之下才算數。
**這個手法值得記住**：任何 `canImport` / `#available` 隔離的程式碼要確認「真的編到了」，
都得用同樣的方式取證，不能只看 build 綠。

探針已移除 `#warning` 噪音，保留為 **API 契約的可執行文件**——未來 SDK 改簽章
（macOS 27+）時，真機 build 會以「PROBE N」精準定位，而非讓 narrator 執行期才炸。

### 3.2 M4 接線 ✅ 已完成（PR #4）
見 §3.4 的設計摘要。

### 3.3 真機驗收結果 ✅

| 驗收項 | 結果 |
|---|---|
| L1 敘事產出 | ✅ 事件 → 一句話 step + 推測目標，品質合理 |
| availability 偵測 | ✅ 正確 |
| 走本地 3B（非 fallback）| ✅ |
| `MemoryStore` 寫入 | ✅ 累加正常 |
| **關 Apple Intelligence → 規則式** | ✅ 標籤確實切換，不中斷 |
| 延遲 | ✅ **1373–2388ms**，符合修訂後的 ~2.5s |
| `/vlm` | 🔒 延後（需 sidecar + ~5–6GB 模型，日常不依賴）|

**延遲目標從 ~300ms 改成 ~2.5s 的理由**（重要，別再改回去）：端上 3B 逐 token 串行生成，
延遲幾乎與輸出長度成正比。300ms 的預算只夠 12–15 個 token，塞不下 6 欄位結構化
step 裡的兩段散文欄位加一個陣列。**這是輸出形狀與模型吞吐的算術，不是調校問題。**
壓過一輪（2659 → 1373ms，靠 `@Guide` 字數上限 + 視窗縮減）就到頭了；
再壓要砍欄位，代價是失去 `inferredGoal`——L1 的價值所在。使用者已裁決維持資訊量。

⚠️ 另一個發現：**`@Guide` 的字數上限模型只當參考、不嚴格遵守**（設 20 字，實測輸出 35 字），
所以延遲會在 1373–2388ms 間浮動。想要穩定收斂得換手段，不是把數字調更小。

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

### 3.4 M4 接線的設計摘要（PR #4）

新增三塊，都在 `packages/CoPartnerKit/Sources/ScriptNarrator/`：

| 檔案 | 作用 |
|---|---|
| `LocalNarrationEnvironment.swift` | **平台門面**：把 `#if canImport(FoundationModels)` 收斂在單一檔案，`AppCoordinator` 一行條件編譯都不用寫。availability 三態（available / unavailable / frameworkAbsent）+ 生後端 + prewarm |
| `L1RollupScheduler.swift` | 決定「**何時**該叫模型」的純邏輯，時鐘外部注入 → 完全確定性、CI 可測 |
| `NarrationLadder.narrateReportingTier` | 回報**實際命中的階梯層級** |

**三個踩過或繞過的坑**（維持它們）：

1. **新活動偵測不能用行數差**。兩個各自獨立的原因：`EventLog.record` 會**就地改寫最後
   一行**（同欄位打字合併、同向 scroll 聚合），使用者打一整段字行數完全不動；
   `EventLogFeed` 又是 ring buffer，飽和後行數固定在 capacity。兩者各自都足以讓
   「count 差」永久歸零、rollup 再也不觸發。改用 `(行數, 末行內容)` 指紋，
   兩條 regression 測試釘住。
2. **階梯必須回報用了哪一層**。只看 `ActionStep` 分不出是 3B 產的還是模板湊的，
   除非比對 `inferredGoal` 的固定字串——文案一改就默默失效，而且失效方式是
   「看起來還是綠的」。
3. **availability 刻意不細分 unavailable 的原因**。`.unavailable` 的關聯值與 reason
   case 名稱是探針**沒驗過**的 API 面。要顯示原因請先加 PROBE 8 驗過再說。

其他：階梯每次 rollup 重建（`FoundationModelsNarrator` 的 `app` 是 init 時綁定的，
沿用同一份會讓 `step.app` 在換 app 後永遠停在舊值）；延遲用 `ContinuousClock` 量
（`Date` 是掛鐘時間，會被 NTP 校時扭曲）；`triggerIntervention` 的 `steps: []` 佔位
已換成 `hotBuffer.recentSteps`，open loop 改用 L1 推測。

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

**合併授權（2026-08-19 使用者裁決）**：
> **CI 三個 job 全綠的 PR，直接合併，不必逐個問。**

理由是流程摩擦：先前每個 PR 都問一次，而使用者每次都答「合併」，
結果是**使用者四度在未合併的分支上做驗收**（PR #7、#11、#20、#21），
每次都白跑一趟。現在的循環是「寫 → CI 綠 → 合併 → 使用者 `git pull` 驗 → 回報」。

⚠️ 這是**合併**的授權，不是**設計**的授權。會改變爆炸半徑的東西
（例如把 `willExecuteActions` 翻成 true，讓 app 第一次真的能執行命令）
仍然要先講清楚設計、拿到同意再做。

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

## 7. ⏭️ 當前待辦：M5 接手全鏈（step 53）

使用者已選定 M5 為 M4 後的下一個里程碑（產品的頭號功能——現在只會「看懂」，M5 才會「動手」）。

### 7.1 computer-use 契約對齊 ✅ 已完成（2026-08-16）

⚠️ 交接文件原本警告「預設值很可能過時」。**查證結果相反：兩個值都是對的。**

| 項目 | 值 | 狀態 |
|---|---|---|
| beta header | `computer-use-2025-11-24` | ✅ 現行 |
| tool type | `computer_20251124` | ✅ 現行 |

真正的缺口是 `HandoffRequestBuilder` 少了 API **必填**欄位，只帶 header 與 type 組不出合法請求：
- `name` — 必須**恰好**是 `"computer"`，不是可自由命名的欄位
- `display_width_px` / `display_height_px`

**支援模型**：`claude-opus-5`、`claude-sonnet-5`、`claude-opus-4-8`、`claude-opus-4-7`、
`claude-opus-4-6`、`claude-sonnet-4-6`、`claude-opus-4-5-20251101`。
較舊模型（Sonnet 4.5 / Haiku 4.5 / Opus 4.1）走**另一份契約** `computer-use-2025-01-24`。

**companion tools**（官方 quick start 的組合）：`text_editor_20250728` /
`str_replace_based_edit_tool`、`bash_20250124` / `bash`——與威脅模型的 argv-only + 沙箱相容。

**設計決定**：`display_width_px` / `display_height_px` **刻意不給預設值**。填錯不會報錯，
只會讓 Claude 回傳的座標全部偏掉（再經 Retina 換算放大，極難歸因）。改為 init 必填；
`CloudRouter.requestBuilder` 連帶改為 optional，未設定拋 `.noRequestBuilder`——
與 `.noTransport` 同一個「未接線就明確失敗」的模式。

**effort 注意**：官方對 computer-use 的 `effort` 建議只涵蓋到 Opus 4.7（`high`）與
4.6/Sonnet 4.6（`medium`，且明講 `max` 只增成本不提準確度）。**Opus 5 不在建議清單裡**——
真機驗收時這是要實測的參數，不是照抄的。

### 7.2 M5 的四塊

1. ✅ **`sandbox-exec` 在 macOS 26 仍可用**（2026-08-17 真機實測）。
   對照測試：無沙箱 `curl` exit=0、加 `(deny network*)` 後 exit=6。
   威脅模型 §6 備援**不需提前啟用**。
2. ✅ **假 SSE `HandoffTransport`**（PR #5）— `SSEFrameParser` + `AnthropicStreamDecoder`
   + `ComputerUseNormalizer`，`SSEByteSource` 可注入。🔒 剩真的 LiteLLM 位元組來源
   （`cd infra/litellm && litellm --config config.yaml`，設 `ANTHROPIC_API_KEY`）。
3. 🔒 **真 `ActionExecutor.performer`** — **M5 只剩這塊沒開始**，見 §7.3。
4. ✅ **接手 HUD**（PR #6）— NSPanel 常駐浮層 + 確認閘門接線。
   附「HUD 預覽」除錯入口（step 54）：真執行端接上前唯一能目視驗證浮層的方式。
   預覽走**完全獨立的路徑**——不建狀態機、不建 executor、不碰 `pendingDecision`，
   決定回呼只關浮層。否則一顆除錯按鈕就成了繞過確認閘門的後門。

驗收清單見 `realmachine-runbook.md` M5 節（對照威脅模型 I1–I10 逐項勾）。

### 7.3 ⏭️ 下一步：真執行端，切成四段（2026-08-17 使用者已同意此順序）

這塊跟 M5 前面幾塊性質不同：**它是唯一會真的動使用者電腦的程式碼**，
而 XPC 連線、code-signing 驗證、sandbox profile 這三樣在 Linux 容器裡一行都跑不到。
所以刻意切成四段，每段都能單獨真機驗，**前三段不執行任何真動作**：

1. ✅ **XPC 骨架**（PR #11，2026-08-18 真機通過）— service pid 與 app pid 不同，
   回報「會執行動作：否」。**`ApprovalToken` 最後決定不過線**：跨程序的值可以被偽造，
   誰連得上誰就能自己編一個。授權留在偽造不了的地方（主 app 內驗 token），
   線上只帶 `actionID` / `generation` 當稽核關聯。
   ⚠️ 同時實測到 service euid = 501（使用者本人）——見威脅模型 §6 修正與 R5。
2. **code-signing requirement 驗證** — 用 `NSXPCListener.setConnectionCodeSigningRequirement`
   交給系統在連線層強制（不要自己查 pid——pid 會被回收再利用，是有名的 TOCTOU 弱點）。
   requirement 從**本組建自己的簽章**推導（同 Team + 指定 bundle id），
   ad-hoc 開發組建沒有 Team ID → 組不出來 → `.unavailable`。
   關鍵不變式寫在 `CallerVerification`：**沒有驗證就不可以有執行能力**——
   第 ④ 段翻開執行能力的那一刻，未驗證的連線自動開始被拒，不依賴任何人記得回來改。
   **必須故意用別的程序去連並確認被拒**（`scripts/xpc-probe.swift`）——
   沒驗過拒絕路徑就等於沒有這道防線。

   **真機實測結果（2026-08-18）**：
   - 外部程序**定址不到**內嵌 service（連線直接 invalidated）→ T7 主防線是 service 的
     「內嵌」類型，驗簽是縱深防禦。威脅模型 R6 已據此改寫，不再含糊。
   - `codesign` 顯示內嵌 `.xpc` 原本是 **ad-hoc 簽**（`TeamIdentifier=not set`），
     app 卻是 Apple Development 簽的 → service 組不出 requirement、主 app 反向驗也必敗。
     修法：`DEVELOPMENT_TEAM` / `CODE_SIGN_STYLE` 移到 `settings.base`，兩個 target 都吃到。
     手動在 Xcode UI 設沒用——`bootstrap.sh` 每次重生專案會蓋掉。
   - **XPC 回呼一律要標 `@Sendable`**。Swift 6 會把 `@MainActor` 環境裡寫的、
     API 沒標 `@Sendable` 的閉包推斷成 MainActor 隔離並插入佇列斷言，
     XPC 從自己的 serial queue 呼叫時 → `_dispatch_assert_queue_fail` 當掉整個 app。
     CI 看不到：編譯得過，要真的有回呼進來才炸。
3. **`sandbox-exec` sbpl** — 產生 profile 並確認限制真的生效。
   沿用 §7.2 那個對照法：無沙箱 exit=0、有沙箱被擋。
4. **`posix_spawn` argv 直呼**（無 shell）— 接上去，第一次真的執行東西。

CI 的 `app` job 會跑 `xcodegen generate` + `xcodebuild build`，所以
**project.yml 加 XPC target 若寫錯，CI 會擋下來**（但 code-signing 相關一律測不到，
`CODE_SIGNING_ALLOWED=NO`）。

### 7.4 step 53–54 dogfood 抓到的四個 focus bug（全部已修並真機驗過）

`FocusChangeTracker` 這個檔在整個專案裡踩坑最多，四次都是**同一個本質**：
拿一個不可靠的東西當視窗身分。留在這裡當之後改動的警示。

| # | 成因 | 症狀 | 修法 |
|---|---|---|---|
| 1 (M2) | 拿 AX `value`（欄位內容）當身分 | 終端機每輸出一字就判定換視窗 | 改用 `windowTitle` |
| 2 (PR #6) | 標題**自己會變**（終端機把尺寸寫進去）| 拉一次視窗 0.1 秒噴 6 行 FOCUS | `windowIdentity` 剝掉易變樣式 |
| 3 (PR #8) | 把「**讀不到**」當成一個身分（空字串）| 標題讀失敗又讀回來，來回噴假 FOCUS | 只有「已知 → 另一個已知」才算換視窗 |
| 4 (PR #9) | **兩個欄位不是在講同一個 app** | `app=備忘錄 win="新增連線"`（AnyDesk 的視窗）| `ownerPID` 對帳，對不上就當未知 |

一併修掉的還有 `inferApp`（PR #8）：原本取視窗**第一行**的 app，而視窗是舊到新排的，
於是每個 step 標的是「這段開始時你在哪」。真機上整串 step 掛著 `CoPartner`，
內容講的卻是 AnyDesk。改成取佔比最高、平手取較晚。
`MemoryStore` 依 app 存 step，這條標錯等於之後全部查錯戶。

**貫穿四次的原則**：漏記看不見、噪音看得見，所以一律**保守偏留**——
正規化只處理有把握的樣式、剝光時退回原值、讀不到擁有者時不擋。
也因此**刻意不用時間節流**當通用後備：它會靜默吃掉真實的快速切換。

### 7.4.1 ⚠️ 未解事件：主 app 被系統以「記憶體過多」終止（2026-08-18 12:50Z）

**紀錄在案，尚未處理**（使用者裁決先記錄、之後再查）。

現象：Xcode 跳「The process has been terminated by the operating system because it is
using too much memory」，`Code 9 / IDEDebugSessionErrorDomain 11`，
`operation_duration_ms = 42668`（跑約 42 秒就被砍）。

**事後量測（同一天稍後、同樣操作）一切正常**：主 app 在 160–210 MB 之間浮動、
XPC service 8.4 MB。所以不是穩態就會發生的事。

**最可能的成因（未證實）**：出事當下跑的是 **PR #15 之前**的 build——那個版本的
XPC service 一啟動就死在 `listener.setConnectionCodeSigningRequirement`，
launchd 反覆重啟，而 Xcode 設定是 `param_debugger_attachToXPC = 1`，
每次重啟都附加一次除錯 session。#15 合併後崩潰迴圈消失，這個現象也沒再出現。
時間軸完全吻合，但**沒有直接證據**。

**其他尚未排除的候選**（都與 XPC 無關，是既有結構）：
- `CaptureEngine` 的 `AsyncStream<TileEvent>` 預設是**無上限緩衝**。消費端在 MainActor
  更新 UI，若生產快於消費就會無限堆積。
- `FoundationModelsNarrator.narrate` **每次呼叫都新建 `LanguageModelSession`**，
  session 是否持有 KV cache、由誰回收，沒查證過。

**下次再遇到要收集的**：哪一個程序在飆（主 app / service）、被砍時到多少 GB、
以及是否有按「開始觀察」（那決定是不是觀察管線造成的——不按就只有 XPC 路徑在跑）。

### 7.4.2 第 ② 段的實測結論

- **崩潰位置已確認**：死掉的 service 程序 Thread 1 堆疊是
  `xpc_connection_set_peer_code_signing_requirement` ← `-[NSXPCListener
  setConnectionCodeSigningRequirement:]` ← `main`。
  **內嵌 XPC service 不可在 listener 層設 requirement**，改成在
  `shouldAcceptNewConnection` 裡對每條連線設（PR #15）。
  ⚠️ 確認的是**位置**，不是 Apple 為何如此設計——這個理解缺口留著，
  第 ③④ 段之前若能補上更好。
- **簽章修好後驗呼叫者真的啟用了**：自檢顯示「驗呼叫者：已啟用：identifier …」。
- **顯示順序的教訓**：這行曾被截斷，而被吃掉的正好是最該看的「驗 service」。
  **診斷輸出要按「驗收要看什麼」排序**，不是按程式裡的欄位順序——
  長字串（requirement 原文）一律放最後。

### 7.6 今晚 XPC 工作的自我審查（2026-08-18 深夜）

#### 7.6.1 誠實的狀態盤點

「沒出錯」不等於「驗過」。分成三層：

| 層級 | 項目 |
|---|---|
| **真機證明過** | service 與 app 是不同 pid；service euid = 501（因此**沒有**權限降級）；外部程序定址不到內嵌 service；`驗呼叫者：已啟用` 且 requirement 字串正確；修好簽章後 `.xpc` 有 Team ID |
| **只是 CI 綠 / 只是沒出錯** | 主 app 反向驗 service（`驗 service：通過` 那一欄**從未被親眼看到**，前一次被截斷、之後沒再確認）；10 秒逾時從未被真的觸發過；`perform()` 這條路徑**一次都沒跑過**（沒有真提議可送） |
| **我曾宣稱但沒證明** | 「listener 層 API 不適用於內嵌 service」——只確認了崩潰**位置**，不知道 Apple 為何如此設計；記憶體事件的成因（見 §7.4.1）純屬推測 |

#### 7.6.2 審查找到並已修的（PR #17）

1. **兩側規則不對稱**：service 端有「沒有驗證就不可以有執行能力」，主 app 端**沒有**
   對應規則——ad-hoc 組建下 `perform()` 照樣把真動作送給從未驗證過身分的 service。
   程式碼註解寫著「一律要求 service 通過驗證」，**那句話是假的**。
   修：`CallerVerification.decideOutbound` + 一條對照測試釘住兩側同形。
2. **被閘門擋下的動作留下零稽核痕跡**（違反 I9）：六條拒絕路徑全在寫稽核前就 throw，
   而那六條正好是最需要事後查得到的。修：每條都先 `blocked …` 再 throw。
3. **探測腳本的手寫 JSON 無人綁住**：`Kind` 一改，腳本會靜默送出解不開的請求，
   失敗長得像「service 拒收」——**看起來像防線生效，其實是腳本壞了**，
   會讓拒絕路徑的驗收得出假的通過。修：測試直接讀該檔抽出字面值來解 + CI `-typecheck`。

#### 7.6.3 ✅ 已裁決：UI 動作執行端納入 M5（成為第 ⑤ 段，2026-08-19）

`ExecutionRequest.from()` 對 `click / typeText / keypress / scroll / screenshot`
一律 throw `.notSandboxable`（正確：UI 動作不經 shell 沙箱，見 R2）。

但這代表**四段計畫做完，能執行的只有 shell 與檔案動作**——而 computer-use 接手的
主體正是點按與輸入。「按熱鍵交棒給 Claude 接手續做」這個產品核心功能，
在四段之外還缺一塊：**主程序內的 AX / CGEvent 執行端**（含 Retina 座標換算、
`ProposedActionParser` 的座標語意、失敗如何回報）。

這塊沒有沙箱可保護（R2），防線只有 confirm-each + 風險分級 + undo。

**使用者已裁決：納入 M5，成為第 ⑤ 段。** 所以 M5 的執行端是五段而不是四段：

| 段 | 內容 | 狀態 |
|---|---|---|
| ① | XPC 骨架 | ✅ 真機通過 |
| ② | 呼叫者 code-signing 驗證 | ✅ 實質完成（`驗 service：` 欄尚未親眼確認）|
| ③ | sandbox-exec sbpl profile | ✅ **真機 7 項全綠**（2026-08-19）|
| ④ | `posix_spawn` argv 直呼（第一次真的執行）| 🔒 |
| ⑤ | **主程序內 AX / CGEvent 執行端**（點按 / 輸入 / 捲動 / 截圖）| 🔒 |

第 ⑤ 段的特殊之處：**它沒有沙箱**。所有防線都在提議進來之前——
本地風險分級、confirm-each、HUD 顯示的是本地產生的動作原文、undo。
另外它有一個第 ③④ 段沒有的技術風險：**座標語意**。
Retina 換算、多螢幕原點、以及 Claude 的座標是對哪一個顯示器下的，
錯了不會報錯，只會點到別的地方——而「點到別的地方」可能比不執行更糟。
`HandoffRequestBuilder` 的 `displayWidthPx` / `displayHeightPx` 刻意沒有預設值
就是為了這個（見 §7.1）。

#### 7.6.4 第 ③ 段（sandbox-exec profile）的計畫

`SbplProfileBuilder` 已存在（step 51），所以第 ③ 段的重點是**證明它在擋**，不是寫它。
但讀過現況後，有三件事得先處理：

**(a) 只測「擋得住」會得到假的通過。**
`(deny default)` 之下，被 spawn 的程式連 dyld 與系統 dylib 都讀不到，
**幾乎任何東西都會失敗**。若只做「無沙箱成功 vs 沙箱失敗」的成對測試，
一個「什麼都擋」的壞 profile 會**全部通過**。
所以必須雙向：
- **負向**：禁止的事在沙箱內失敗、無沙箱時成功（證明是 profile 擋的，不是本來就會失敗）
- **正向**：允許的事在沙箱內**仍然成功**（證明 profile 沒有把該放的也擋掉）
沒有正向對照，這一段的驗收沒有意義。

**(b) 現行 profile 幾乎確定跑不起來任何程式。**
只 `(allow file-read* (subpath workspace))` 不足以讓一個 binary 載入。
第 ③ 段要補的是「讓白名單內的工具真的能跑」所需的最小讀取集合，
而每加一條都要有正向測試說明它為何必要——否則會退化成逐條放寬直到能動。

**(c) 路徑沒有跳脫。**
`workspace` / `deniedSubpaths` 直接內插進 `"..."`，含引號或反斜線的路徑會破壞
profile 結構。這是**安全設定裡的注入面**，且完全是 CI 可測的純值問題。

CI 測得到：profile 字串的產生（規則順序、跳脫、最後一條規則勝出的語意）。
只能真機：`sandbox-exec` 實際套用的行為。

#### 7.6.5 第 ④ 段之前必須關掉的門（2026-08-20 全數打勾，已翻開）

`ExecutorService.willExecuteActions` 翻成 `true` 之前，逐項確認：

- [x] 沒有驗證就不可以有執行能力（service 端，`CallerVerification.decide`）
- [x] 驗不了 service 身分就不送真動作（主 app 端，`decideOutbound`，PR #17）
- [x] 被擋的動作留稽核（I9，PR #17）
- [x] **`驗 service：通過` 親眼確認**（2026-08-19）：雙向驗證都成立，
      requirement 字串的 bundle id 與 Team ID 皆吻合
- [x] sbpl profile 的正向與負向對照都通過（第 ③ 段，7 項全綠 0 失敗 0 無效）
- [x] 路徑跳脫（第 ③ 段 (c)）
- [x] 路徑先解符號連結（真機抓到：給 `/tmp/x` 的規則對 `/private/tmp/x` 永遠不匹配）
- [x] `scripts/xpc-probe.swift` 在驗簽啟用後重跑（2026-08-19）：結果不變，
      仍是「連線失效（invalidated）」。再次確認 R6——擋住外部程序的主力是
      **內嵌 service 的定址範圍**，驗簽是縱深防禦
- [x] 逾時的**邏輯**有 CI 覆蓋（`SingleCompletionTests`，含 200 輪多執行緒競態）。
      ⚠️ **誠實的界線**：CI 驗的是「多條完成路徑只會完成一次」這個保證，
      不是真實 XPC 逾時路徑本身。後者要靠一個故意不回覆的 service 才觸發得到，
      而為了測試在正式程式碼裡開一個「讓 service 卡住」的能力，代價大於收益。
      我們**有這個失敗模式的直接證據**——step 53.2 那次 service 啟動就崩潰、
      自檢永遠卡在「檢測中…」，逾時就是為它加的，而它現在不可能再無聲發生。

#### 7.6.6 記憶體：範圍已被真機觀察砍掉一半（2026-08-21）

**使用者回報（決定性）：**

> 在沒有開啟觀察下，持續開著 CoPartner 就會跳出記憶體告警。

這一句直接**排除**了原本記在這裡的兩個主要嫌疑，因為兩者都只在按下
「開始觀察」之後才存在：

- ~~`CaptureEngine.start` 的無上限 `AsyncStream<TileEvent>`~~ —— 沒 start 就不存在
- ~~`ocrTick` 每 3 秒的全顯示器截圖（5K BGRA 約 59 MB／張）~~ —— 沒 start 就不會跑

（兩者仍是**觀察中**那條曲線的嫌疑，只是不再是這個告警的成因。
`AsyncStream` 那條依舊**先別修**：等閒置這條查完、再拿觀察中的曲線去驗它。）

**閒置路徑上我們自己的程式碼什麼都沒跑。** `init()` 只註冊熱鍵；`MemoryStore`、
`EventLogFeed` 都有容量上限，而且要 `startPipeline` 才會被餵東西；所有 `Task`
都在 `startPipeline` 之後才建立。剩下的嫌疑因此落在框架層——最可疑的是
`MenuBarExtra` + `.menuBarExtraStyle(.window)`（每次開合重建 `NSHostingView`），
以及 `NSPasteboard` / AX 之類我們只在按鈕路徑上碰的東西。

**但這已經不能靠讀原始碼往下推了，需要數字。**

##### 量測方式：開選單時取樣（step 53.7）

選單裡多一行記憶體摘要：目前／起始／峰值／成長 MB per hour ＋ 樣本數與時間跨度。

**刻意不用定時器。** 要量的正是閒置路徑，在上面裝一個會定時醒來的東西等於在被觀察
的對象裡加一個新的觀察者——它自己會配置、會讓 runloop 醒來、會改變我們想量的曲線。
改成「每次打開選單取一個樣」，背景成本恰好是零。代價是取樣間隔不規則，所以斜率一律
用**首末兩點**算並報成 MB/小時，時間跨度不足一分鐘時直接不報
（`MemorySampleLog`，CI 覆蓋）。`toggleObserving` 也各取一次，
讓「閒置」與「觀察中」的斜率在同一條曲線上分得開。

用 `phys_footprint` 而不是 `resident_size`：前者才是 Activity Monitor「記憶體」欄
與系統跳告警／終止程序時看的那個數字。

##### 第一輪真機結果（2026-08-21）：**閒置沒有洩漏**

| 時間 | 目前 | 峰值 | 整體斜率 |
|---|---|---|---|
| 0 分 | 26 MB | 26 MB | — |
| 51 分 | 30 MB | 30 MB | +5 MB/小時 |
| 55 分 | 30 MB | 30 MB | +4 MB/小時 |
| 59 分 | 30 MB | 30 MB | +4 MB/小時 |

關鍵在**峰值 = 目前 = 30 MB，連續三個樣本橫跨 51→59 分鐘完全沒動**。
26→30 是啟動暖機，之後就平了。整體 30 MB 離「跳記憶體告警」差了兩三個數量級。

**這一輪同時抓到摘要本身的缺陷。** 那個「+4 MB/小時」是暖機的 4 MB 被攤到一小時上
算出來的，不是還在漲的斜率。整體斜率當初是為了避開相鄰差的雜訊而選的，結果換成另一種
誤導：它分不出「一次性暖機後持平」與「持續成長」，而那正是我們唯一想知道的事。
已加上**近期斜率**（最後 3 筆）並排在整體前面，`< 1 MB/小時` 直接標「近期持平」。

##### 第二輪（觀察中，43 分鐘）：上去又下來，不是無上限成長

```
記憶體：130 MB（起始 26・峰值 162 MB）・近期 -247 MB/小時・整體 +144 MB/小時（10 樣本／43 分）
```

- 閒置 30 MB → 觀察中衝到 **162 MB** → 回落到 **130 MB**，近期斜率是**負的**。
- 上去又回來 ＝ 大工作集 + 有在回收。無上限洩漏的曲線只會一路往上，不會掉。
- 43 分鐘沒有出現任何記憶體告警。

**這一輪抓到摘要的第二個缺陷。** 「整體 +144 MB/小時」是把「閒置 30 MB → 觀察中 130 MB」
這個**階段落差**攤成了速率。閒置與觀察中是兩個不同的工作集，把它們接成一條線取斜率，
得到的是「落差 ÷ 總時間」——一個沒有物理意義、但看起來很像成長率的數字。
已修：斜率與峰值都**不跨越狀態邊界**（`MemorySample.regime`），
`toggleObserving` 前後各取一次樣，讓新階段一開始就有起點。

兩輪的共同教訓寫在 `MemorySampleLog` 檔頭：**一個看起來像資料的猜測，比「不知道」更糟**
——它會讓人停止繼續查，或往錯的方向查。

##### 第三輪（停止觀察後）：掉了，但沒掉回底線

```
92 MB（起始 26・峰值 162 MB）・近期斜率待累積・整體 +73 MB/小時（15 樣本／55 分）
```

停止觀察後 130 → 92 MB，繼續在掉，但沒回到原本的 30 MB。

這把問題收斂成一個很具體的問句：**92 MB 是「留著不放的快取」還是「每跑一輪就往上疊」？**

- 前者無害。這一輪 `本地模型：可用（Apple Intelligence）`——觀察期間載入了 3B 模型，
  那東西不會因為停止觀察就卸載，幾十 MB 的常駐完全合理。
- 後者才是真的漏。

**分辨方法只有一個：開關觀察幾輪，看閒置的底線會不會一輪比一輪高。**
摘要那一行只講當下這一段，看不到這件事，所以加了**階段軌跡**：

```
階段：閒置 26→30・觀察中 30→130（峰 162）・閒置 130→92 MB
```

疊高（30 → 92 → 150 → …）＝ 真的在漏；穩定（30 → 92 → 92 → …）＝ 快取。

##### 第四輪（第二次開關觀察）：**ratchet 確認**

兩次「已停止觀察」當下的讀數可以直接比：

| 輪次 | 停止後 | 該輪峰值 | 當時「記憶 N 筆」 |
|---|---|---|---|
| 初始閒置 | 30 MB | 30 MB | — |
| 第 1 輪 | **92 MB** | 162 MB | 32 |
| 第 2 輪 | **136 MB** | 181 MB | 41 |

閒置底線 30 → 92 → 136，每輪往上疊約 44 MB。**這是 ratchet，不是快取。**

⚠️ **先前的判斷要更正**：§7.6.6 第二輪之後寫的「兩條曲線的形狀都不像洩漏、
在拿到 Activity Monitor 之前不應該改任何程式碼」是建立在只有一輪資料上的。
兩輪之後形狀反過來了。

##### 找到的具體機制候選（尚未證實）

`FoundationModelsNarrator.narrate` **每產生一個 step 就建一個新的
`LanguageModelSession`**，`warmUp` 也另外建一個用完就丟：

```swift
public func narrate(_ lines: [String]) async -> ActionStep? {
    let session = LanguageModelSession(instructions: Self.instructions)   // ← 每個 step 一個
    ...
}
public func warmUp() async {
    let session = LanguageModelSession(instructions: Self.instructions)   // ← 建了就丟
    session.prewarm()
}
```

而同一個檔案自己的註解寫的是相反的意圖：

> narrator 因此與「現在在哪個 app」無關，**可以長期存活一份**，
> prewarm 的效果才不會被每次重建丟掉。

**narrator 確實長期存活，但它裡面的 session 每次呼叫都重建**——註解描述的意圖在下一層
被推翻了。這與 `AppCoordinator` 那段「階梯只建一次」的註解是同一種落差。
3B 模型的一個 session 帶 KV cache，量級正好在幾 MB。

##### 兩個假設都符合現有資料，一個開關就能分辨

| 假設 | 預測 |
|---|---|
| **每個 step 一個 session** | 成長跟著 **step 數**走（32→41 筆 ＝ +44 MB，約 5 MB/step）|
| **每輪 pipeline 沒放乾淨** | 成長跟著 **開關次數**走 |

兩者在現有的兩個點上無法區分（step 數與開關次數同時增加）。

**分辨方法：關掉 Apple Intelligence 再跑一輪。** 敘事會自動降級成規則式
（M4 已驗過這個切換不中斷），完全不會建立任何 `LanguageModelSession`，
但 pipeline 的開關照舊。

- ratchet 消失 → 是 session，修 `FoundationModelsNarrator`
- ratchet 照舊 → 是 pipeline，往 `CaptureEngine` / `SCStream` 查

⚠️ **在分辨出來之前不要改 `FoundationModelsNarrator`。** 改成重用 session 會帶來
另一個問題（`LanguageModelSession` 會累積 transcript，最後撞上 context 上限），
那是一個需要設計的取捨——不該為了一個還沒證實的假設去付。

##### 第五輪（**關掉 Apple Intelligence**）：模型 session 極可能是主因

軌跡（新版選單那一行，敘事全程走規則式、一個 `LanguageModelSession` 都沒建）：

```
階段：觀察中 30→145・閒置 145→65・觀察中 65→140（峰 182）・閒置 140→75 MB
```

閒置底線並排：

| | 第 1 輪後 | 第 2 輪後 | 增量 |
|---|---|---|---|
| 開著 Apple Intelligence | 92 MB | 136 MB | +62, **+44** |
| 關掉 Apple Intelligence | 65 MB | 75 MB | +35, **+10** |

關掉模型之後 ratchet 從「每輪 +44 且不收斂」變成「+35 → +10，明顯在收斂」。
**收斂的形狀是一次性成本**（載入 Metal / Vision / SCStream 這些框架），不是洩漏。
觀察中的峰值兩組差不多（162/181 vs 145/182），符合「峰值由截圖主導、且是暫時的」。

⚠️ **這是方向性證據，不是嚴格對照。** 兩個已知的瑕疵：

1. **觀察期長度差很多。** 這一輪每次只觀察約一分鐘（劇本時間戳 20:14:28 → 20:15:42），
   `記憶 1 筆` / `3 筆`；開著模型那兩輪是幾十分鐘、32 → 41 筆。短週期同時也少了截圖的量。
2. **閒置讀數是停止後幾秒內取的**（樣本跨度 0 分），記憶體那時還在往下掉——
   軌跡自己就顯示 `閒置 145→65`，那一段自己掉了 80 MB。所以 75 大概還沒到底。

##### 取樣改成落檔（使用者裁決 2026-09-02：「就把這些數值記錄成 log 後續自行分析」）

`~/Library/Application Support/CoPartner/Diagnostics/memory-log.tsv`
（路徑也顯示在選單裡，可直接複製）。欄位：

```
時間	足跡MB	狀態	記憶step數	來源
2026-09-02T20:14:28+08:00	30.2	閒置	0	transition
```

**`來源`那一欄是重點**：它讓「停止後幾秒取的」與「等它落定才取的」分得開，
而先前每一輪診斷都栽在分不開這件事上。四種來源：

| 來源 | 何時 |
|---|---|
| `menu` | 打開選單 |
| `transition` | 開始／停止觀察的**前後各一次** |
| `tick` | 觀察中每 15 秒——**搭既有的敘事迴圈，不另外喚醒任何東西** |
| `settle` | 停止觀察 **60 秒後**的落定值 |

`settle` 直接補掉先前每一輪的共同瑕疵：閒置讀數都是停止後幾秒內取的，
而記憶體那時還在往下掉（軌跡自己顯示過 `閒置 145→65`，一段自己掉了 80 MB）。
它**不是定時器**——一次停止只排一次，下一次狀態切換就取消。

日誌有行數上限（20000 行，超過裁掉最舊的一半）。
一個為了診斷記憶體而無上限成長的日誌會很難堪。

##### 下一輪要怎麼跑才算嚴格對照

同一組步驟做兩次，一次開著 Apple Intelligence、一次關掉：

1. 開始觀察，**正常操作 5–10 分鐘**（兩次的操作量要差不多）
2. 停止觀察，**等超過一分鐘**讓 `settle` 那一筆寫進去
3. 重複兩輪

然後把 `memory-log.tsv` 整個交出來即可——不必再截圖念數字。
分析時只看 `source=settle` 那幾行的「閒置底線」：關掉模型時收斂、開著時不收斂
→ 確認是 session。

##### 第六輪（第一份真實日誌，2026-09-02）：**主要假設被推翻**

第一次拿到完整曲線而不是截圖。兩輪觀察，各約 6 分鐘。

| 段 | 狀態 | 時間 | 足跡 | tick 斜率 |
|---|---|---|---|---|
| 1 | 閒置 | — | 26 → 30 MB | — |
| 2 | 觀察中 | 6.9 分 | 30 → 165 MB | **+83 MB/小時** |
| 3 | 閒置 | 1.4 分 | 165 → 109 MB | — |
| 4 | 觀察中 | 5.5 分 | 109 → 189 MB | **+110 MB/小時** |
| 5 | 閒置 | 1.1 分 | 189 → 157 MB | — |

**① 成長不是跟著 step 走 → `LanguageModelSession` 假設被推翻。**

日誌裡有好幾段「step 數完全沒動、記憶體照樣在漲」：

```
20:35:04→20:35:20  step 都是 2   104.1→104.3 MB
20:35:20→20:35:35  step 都是 2   104.3→104.6 MB
20:37:42→20:37:58  step 都是 11  110.9→111.2 MB
20:40:30→20:40:45  step 都是 22  118.1→118.2 MB
```

每個 step 平均只帶 +0.24 ~ +0.39 MB，而**沒有新 step 的 15 秒照樣漲 0.1~0.3 MB**。
`FoundationModelsNarrator` 每個 step 建一個 session 仍然不是好寫法，但它**不是**這個
ratchet 的主因。先前「關掉 Apple Intelligence 之後 ratchet 變小」的觀察另有解釋：
那一輪的觀察期只有一分鐘。

**② 真正的大宗在「開始觀察的頭 15 秒」，兩輪都是。**

```
20:34:18→20:34:34  step 都是 0   31.8→109.9 MB（+78.1）
20:42:37→20:42:52  step 都是 0   108.0→181.0 MB（+73.0）
```

一次配置約 75 MB，發生在 step 產生之前，**與敘事完全無關**。而停止觀察後只還回一部分：
閒置底線 30 → 109 → 157。這正好是「擷取管線建起來的東西沒有全部放掉」的形狀，
嫌疑回到 `CaptureEngine` / `SCStream` ——也就是我先前叫大家別動的那一條。

**③ 觀察中會週期性回收 ~25 MB**（181.5→156.9、169.0→144.1），所以是鋸齒不是純上升。

**④ 一個我差點講錯的東西。** 有兩筆 `menu` 取樣後 1–4 秒內跳了 +40 MB，看起來像
「打開選單很貴」。但**閒置時的 menu 取樣跳動是 +0.0 / +0.1 MB**——那兩次都發生在觀察中，
所以是擷取管線的尖峰，不是選單。差一點就把一個假的結論寫進文件。

##### 日誌格式 v2（這一輪暴露的兩個缺口）

1. **日誌沒有記錄 Apple Intelligence 是開還是關**——而整個診斷的關鍵對照就是那個開關。
   分析到一半才發現只能靠記憶補，而記憶正是這一整串診斷裡最不可靠的環節。
   → 加「模型」欄。
2. **`settle` 的 60 秒還不夠**：60 秒那一筆是 124.6 MB，25 秒後卻已經掉到 108.9。
   → 改成取一條衰減曲線（60 秒 / 5 分鐘 / 15 分鐘），讓「掉到哪裡不再掉」自己浮出來。
3. 開始觀察的頭一分鐘改用 **3 秒**取樣間隔：15 秒的間隔只能告訴我們那 75 MB「漲了」，
   看不出是一次大配置還是一連串小配置——那兩件事要查的地方完全不同。

##### 那個告警到底是什麼？三個還沒排除的可能

1. **告警發生在觀察中**，而回報時記成了閒置。閒置這條現在已清，
   下一步就是量觀察中那條曲線——原本那兩個嫌疑（無上限 `AsyncStream`、
   每 3 秒全螢幕截圖）**在那條曲線上仍然成立**。
2. **漲的不是主程序。** `phys_footprint` 只量這個 task。XPC service 是另一個程序，
   而且 WindowServer 也會替我們持有東西。（service 由 launchd 閒置回收，
   要它累積一小時不太可能，但沒實測過就不能說排除。）
3. **告警根本來自別的 app**，CoPartner 只是剛好開著。macOS 的「應用程式記憶體不足」
   對話框列的是最大宗的耗用者——30 MB 不可能上榜。

##### 下一步（真機）

1. **開關觀察三、四輪**（每輪觀察十幾分鐘就好），看階段軌跡裡**閒置的底線**
   會不會一輪比一輪高。這是目前唯一能分辨「留著不放的快取」與「真的在漏」的觀察，
   而且比跑一兩個小時快得多。
2. **觀察中跑久一點**（一兩個小時），看本階段的近期斜率會不會由負轉正並持續為正。
   43 分鐘的一段還不足以排除慢速洩漏——但已足以排除「快速無上限成長」。
3. 若近期斜率明顯且持續為正 → 用 Instruments Allocations 抓是誰；
   線性成長指向無上限緩衝（`CaptureEngine` 的 `AsyncStream`），
   階梯式跳升指向大塊配置（每 3 秒的全顯示器截圖）。
4. **告警再次出現時，當下截一張 Activity Monitor**（記憶體分頁、按記憶體欄排序、
   看最下方的「記憶體壓力」是不是黃／紅）。那張圖能一次分辨上面三種可能，
   比任何推理都快。

**現階段的結論**：兩輪都沒有重現那個告警，而且兩條曲線的形狀都不像洩漏
（閒置持平、觀察中上去又回來）。在拿到 Activity Monitor 那張圖之前，
不應該再為這件事改任何程式碼——包括 `CaptureEngine` 那條 `AsyncStream`。

#### 7.6.6b 第 ③ 段的過程紀錄（五輪收斂，值得留著）

profile 內容本身不難，難的是**證明它在擋**。五輪各自推翻了一個東西：

| 輪 | 症狀 | 學到什麼 |
|---|---|---|
| 1 | 沙箱內全部 `rc=134`（SIGABRT），**含正向案例** | 只測「擋得住」會得到假的通過。腳本自己犯了它要防的錯——有正向對照卻沒讓負向**依賴**它 |
| 2 | stderr 全空 | `(deny default)` 連「寫到終端機」都擋。指望子程序自己開口是錯的假設——被擋住的正是「開口」。改讀統一日誌 |
| 3 | 起得來了、`rc=1` | 能 exec 不等於能讀（載入器要讀 binary 本身）。metadata 逐條補補不完 → 刻意放寬，但要說清取捨 |
| 4 | 規則永遠不匹配 | **路徑要先 `realpath`**。而且 `URL.resolvingSymlinksInPath()` 會把 `/private` 再拿掉，等於白解析 |
| 5 | 半套規則 | `/dev/dtracehelper` 是讀寫開啟的，只放讀跟沒放一樣——但 profile 裡看起來「已經處理過了」 |

**貫穿五輪的方法**：一次只加一個假設 + 一個量測工具，讓機器說話而不是繼續猜。
每條規則的註解都寫明「哪一則真機日誌要求了它」——沙箱規則多放一條看不見代價，
所以每條都要說得出來源。

#### 7.6.6c 第 ④ 段的切法

第 ④ 段是**第一次真的執行東西**，因此再切一次，讓「能執行」這件事單獨成為
一個可以被審視的改動：

| 切片 | 內容 | 風險 |
|---|---|---|
| ④-A | **純值層**：`SandboxedCommand`（argv 組成）、結果分類、輸出截斷 | 無——不給任何執行能力 |
| ④-B | XPC service 端的 `posix_spawn` + 逾時 kill + 輸出收集 | 有程式碼但仍不啟用 |
| ④-C | **翻開 `willExecuteActions = true`** | 這一刻起 app 真的會動手 |

④-A 已完成（PR #23）。安全性其實幾乎全在 ④-A：`posix_spawn` 本身不會出錯，
錯的是餵給它什麼，而那完全是純值、CI 驗得到。

④-C 是**單獨一個改動**、而且只有一行。這樣切的理由：翻開執行能力如果混在
一大包程式碼裡，沒有人（包括我）能真的審完；單獨一行則可以逐項對照門禁清單。
翻開的同時，`CallerVerification` 會自動要求呼叫者驗證——那個結構性保證
就是為這一刻寫的。

**④-C 已於 2026-08-20 翻開（step 53.5）。** 從這一刻起 app 真的會執行東西，
能力範圍是：只有 `shell`、只有固定表裡七個唯讀工具、只能寫沙箱工作目錄、
斷網、家目錄關閉、秘密路徑另外 deny、檔案動作明確拒絕，而且每個動作仍需
本地風險分級 + HUD 人工確認，⌃⌥⌘. 隨時全鏈中止。

**出事時的第一動作**：把 `ExecutorService.willExecuteActions` 翻回 `false`。
它被刻意寫成一行、一個事實，就是為了這個時刻——翻回去之後執行路徑在 guard
後面一次都不會跑，其餘功能（觀察、劇本、HUD、乾跑）全部照舊。

#### 7.6.6d 第一次真執行怎麼驗（step 53.5 驗收步驟）

雲端傳輸還沒接，所以用選單裡橘色的「**執行測試**」送一個**本地合成提議**。
它走的是與真提議完全相同的路徑，只有提議的來源不同。

1. `git pull` + `./scripts/bootstrap.sh` + ⌘R
2. 按「執行測試」
3. HUD 出現，顯示的是**本地風險分級**的判定（不是雲端說的）
4. 按「執行」
5. 看選單裡的執行端那一行：應該是
   `執行端：✅ 真執行成功・處置 succeeded` 加一行 `stdout：CoPartner 第一次真執行 <UUID>`

**判定條件刻意是「stdout 裡有那串隨機標記」，不是 `didExecute == true`。**
沙箱擋掉讀取時 `cat` 照樣會結束、`didExecute` 照樣是 true，stdout 卻是空的——
拿 `didExecute` 當驗收條件會把「被沙箱擋住」讀成「執行成功」。
標記帶 UUID 則是為了讓「這次真的讀到了」與「讀到上一次留下的東西」分得開。

按「略過」或「停止」時執行端那一行會顯示「沒有執行回報」——
上一次的 stdout 會在開始前先被清掉，留著舊證據比沒有證據更糟。

#### 7.6.7 建議的下一步

1. 合併 PR #17，`./scripts/bootstrap.sh` + ⌘R，按「XPC 自檢」——
   這次要**確認 `驗 service：` 那一欄**（顯示順序已修，看得到了）。
2. 裁決 §7.6.3：UI 動作執行端要不要排進 M5。
3. ✅ 第 ③ 段已開始：(c) 路徑跳脫已完成（見下）。接著是 (a)(b) 的對照測試設計。

### 7.5 已知但刻意未處理

**L1 會編故事。** 真機實例：終端機視窗標題是 `CoPartner — -zsh — 100×34`，
模型把它當成「一台叫 CoPartner 的遠端機器」，配上 AnyDesk 就腦補出
「與 CoPartner 進行**視訊會議**」——日誌裡沒有任何視訊訊號。
指令已明寫「禁止臆測日誌沒有的資訊」，3B 壓不住。

這不是膠水的 bug（事件本身乾淨），是 L1 品質調校，與 M5 是兩條線。
真要處理大概是收緊 prompt，或給 `inferredGoal` 一個「證據不足就寫不確定」的硬約束。

**同一個 app 內換視窗仍會記 FOCUS** 這條路徑只有 CI 測試蓋到，
step 54 的 dogfood 沒驗到（那次全程沒在同 app 內換視窗）。
下次 dogfood 開兩個終端機視窗切一下就能補驗。

## 8. 更之後的路線

- **M3 記憶真 vec0**（step 36）— 盲寫風險低（sqlite-vec C API 穩定），但要裝 sqlite-vec + 跑 8hr 驗磁碟量
- **M1 影片 CPU**（step 24）— 前置 step 23.5 擷取 CPU 優化（只 hash dirty tile + async GPU
  + 自適應幀率），建議配 Instruments 抓真熱點
- **M6 隱私最終審查**（step 58）
- **真 `/vlm`**（M4 延後項）— 需 sidecar + ~5–6GB Qwen2.5-VL 下載

以及使用者提出但尚未做的產品需求：**sidecar 打包/託管**（app 自己 spawn 子程序、
結束時收掉、健康檢查重啟），讓 `/vlm` 也不需使用者手動啟動。
