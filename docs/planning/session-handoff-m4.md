# Session 交接 — 從 M2 完成到 M4 開工

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
