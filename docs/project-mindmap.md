# CoPartner 專案心智圖與進度全景

> **單一視覺入口**：把整個專案——產品理念、系統架構、實作進度、里程碑戰績、安全邊界、版本階梯——收在一份文件裡，並在每個節點標上**真實進度**。
> 事實來源：`docs/planning/implementation-backlog.md`（步級）、`docs/planning/realmachine-runbook.md`（真機驗收）、`docs/planning/session-handoff.md`（脈絡）、git 歷史（42 個已合併 PR）。
> 最後同步：2026-09-02（`main` @ `a6d5dfd`）。

**狀態圖例**

| 標記 | 意義 |
|---|---|
| ✅ | 完成（CI 綠，或真機驗收通過）|
| 🔄 | 進行中 |
| 🔒 | 邏輯／程式碼已完成，等真機或真後端驗證 |
| ⏸ | 已評估過、刻意延後 |
| ⬜ | 未開始 |

> 🖼️ **做簡報的話**：本文件所有圖表已匯出成 SVG／PNG 放在 [`docs/assets/diagrams/`](assets/diagrams/)，
> 搭配 [`docs/planning/ppt-material.md`](planning/ppt-material.md) 的投影片大綱與講稿即可直接開工。
> 想直接投影或截圖的話，[`docs/assets/panorama.html`](assets/panorama.html) 是同樣內容的**單頁視覺版**；
> 要 PowerPoint 的話，[`docs/assets/deck/`](assets/deck/) 是做好的 20 頁 .pptx，每頁附講稿。

---

## 1. 一頁看懂

| 面向 | 現況 |
|---|---|
| **產品** | macOS 常駐 menu bar 的 ambient AI 助理：持續把你的操作寫成「操作劇本」，按熱鍵交棒給雲端 Claude 續做 |
| **階段** | **可運作的軟體**，不是骨架。app 在真機上持續觀察並敘事；執行能力已翻開（沙箱內、人工確認後），第一次真執行的驗收回報待補 |
| **步級進度** | **60 / 66 完成（91%）**——原 58 步 backlog，其中 step 53 展開成 53.1–53.7 |
| **里程碑** | M0 ✅・M1 ⬜・M2 ✅・M2.5 ✅・M3 ⬜・M4 ✅・**M5 🔄 大半已真機驗過**・M6 ⬜ |
| **程式碼** | Swift 8,606 行（100 檔）／測試 6,161 行（72 檔）／**595 個 XCTest**；Python sidecar 254 行 ／ 15 個 pytest |
| **交付節奏** | **48 個 PR 已合併**進 `main`，全部走 CI 三 job（macos-15）：`swift`・`python`・`app` |
| **最近里程** | 2026-08-20 **第一次真的執行命令**（`cat` 讀回檔案，UUID 對得上）；2026-09-02 記憶體洩漏定位並修復（+151 → **+7 MB/小時**）；2026-09-03 **第一次真的動使用者的電腦**（HUD 確認後畫面捲動） |
| **下一步** | 接上真雲端 SSE 來源；M5 完整驗收（I1–I10 逐項勾） |

---

## 2. 全景心智圖：這個專案是什麼

```mermaid
mindmap
  root((CoPartner))
    三大理念
      看得省 Smart Capture
        foveated 中央窩擷取
        dirty-region 增量更新
        tile 冷熱狀態機
        ✅ M0 真機通過 idle 9%
      記得清 Script Narrator
        L0 事件日誌 模板
        L1 ActionStep 本地 3B
        L2 段落摘要
        ✅ M4 真機通過 1373-2388ms
      交棒快 Cloud Takeover
        熱鍵 ⌃⌥⌘Space
        ContextEnvelope 因果史
        Claude computer-use
        🔄 M5 執行端已翻開
    橫切關注
      隱私閘門
        PII 遮罩 ✅ 真機驗過
        app 黑名單 🔒 待 M6
        PIPL 跨境阻擋 🔒
      安全邊界
        ApprovalToken 型別層閘門
        風險分級 low medium high
        sandbox-exec sbpl ✅ 7 項全綠
        XPC 雙向驗簽 ✅ 真機
        kill-switch ⌃⌥⌘.
      本地優先
        敏感資料不出境
        ADR-0005 ADR-0007
    目標平台
      Mac mini M4 Apple Silicon
      macOS 26 Tahoe 首要
      Sequoia 15 次要
```

---

## 3. 系統架構心智圖：模組 × 檔案 × 狀態

七個 Swift target 共 **84 個原始檔**，加上 app 端 16 檔。核心原則：**平台重活藏在 protocol 後、CI 用假後端驗邏輯、真後端沒接就 `throw` 不假裝成功**。

```mermaid
mindmap
  root((CoPartnerKit))
    CaptureEngine 31 檔 1784 行
      擷取來源
        SCKFrameProducer ScreenCaptureSource ✅ 真機
        DirtyRegionResolver ✅
        FrameProducer 有界緩衝 ✅ 修過洩漏
      Tile 引擎
        TileGrid TileHashComputer TileHashDiff ✅
        TileStateMachine 冷熱四態 ✅
        PeriodicityDetector 影片偵測 ✅
        CapturePyramid 多解析度 ✅
      注意力
        AttentionModel 事件加權能量 ✅
        AttentionHeatmap 衰減熱圖 ✅
        FocusRegionResolver AX 焦點 ✅
      文字擷取
        OCRCropPlanner 只切焦點區 ✅ 吞吐 18%
        OCRRegionMapper VisionTextRecognizer ✅
        TextSourcePolicy AX 優先 ✅
      隱私
        SensitiveRegionMask ✅
        CaptureBlacklist ✅
        AttentionPrivacyGuard ✅
      持久化
        ReferenceDeltaStore RebaselinePolicy ✅
    ActionExecutor 19 檔 1789 行
      閘門與授權
        TakeoverSessionModel HUD 狀態機 ✅ 真機
        ApprovalToken internal init ✅
        SingleCompletion 只完成一次 ✅ 多執行緒撞過
        CallerVerification 沒驗證就沒能力 ✅ 真機
      風險判定
        RiskClassifier ✅
        DangerousCommandDetector 保守偏殺 ✅
        UIActionGate ✅
      沙箱執行
        SandboxPolicy SbplProfileBuilder ✅ 7 項全綠
        SandboxedCommand argv 組成 ✅
        SandboxWorkspace PathAllowlist ✅
        RateLimiter 迴圈熔斷 ✅
        ExecutionWire 稽核四態 ✅
      UI 動作
        ScreenCoordinateMapper 無 backingScale ✅
        KeyChord VirtualKeyMap 跨模組不變式 ✅
        🔒 willPerformUIActions 待翻開
      UndoStack barrier 機制 ✅
    ScriptNarrator 14 檔 1006 行
      L0 層
        EventFormatter EventLogFeed ✅
        InputEventTranslator ✅
        PIIMasker 前置遮罩 ✅ 真機驗過
        FocusChangeTracker ✅ 修過四類同源 bug
      L1 層
        NarrationLadder 回報實際層級 ✅
        RuleBasedNarrator 保底 ✅
        FoundationModelsNarrator 本地 3B ✅ 真機
        LocalNarrationEnvironment 平台門面 ✅
        L1RollupScheduler ✅
      L2Summarizer 段落摘要 ✅
      FoundationModelsProbe 七項簽章探針 ✅
    CloudRouter 10 檔 858 行
      EnvelopeBuilder 打包因果史 ✅
      EgressGate 出境閘門 ✅
      HandoffRequestBuilder 契約已對齊 ✅
      ComputerUseNormalizer 真形狀翻譯 ✅
      ProposedActionParser 拒未知不猜 ✅
      SSEFrameParser AnthropicStreamDecoder ✅ 假來源驗過
      RetinaCoordinateMapper ✅
      🔒 真雲端來源待接
    CoPartnerCore 4 檔 472 行
      Models ActionStep ContextEnvelope ProposedAction ✅
      CaptureSessionState ✅
      MemorySampleLog 診斷純值層 ✅
    MemoryStore 5 檔 174 行
      L1HotBuffer MemoryStore VectorIndex ✅
      SQLiteVecIndex 誠實佔位 🔒 step 36
    SbplTool 1 檔 62 行
      沙箱驗證用 CLI ✅
```

**app 端**（`apps/CoPartner/`，16 檔 2,461 行）：

| 分區 | 檔案 | 狀態 |
|---|---|---|
| 主程序 | `CoPartnerApp`・`AppCoordinator`・`MenuBarContentView`・`SettingsView` | ✅ 真機 |
| 接手 HUD | `TakeoverHUDPanel`・`TakeoverHUDView` | ✅ 真機通過 |
| 執行端 | `XPCActionPerformer`・`UIActionPerformer`・`ScreenGeometryProvider` | ✅ shell／🔒 UI 旗標待翻 |
| XPC service | `Executor/ExecutorService`・`SandboxedCommandRunner`・`main` | ✅ 真機（pid 分離、驗簽通過）|
| 共用 | `Shared/ExecutorXPCProtocol`・`CodeSigningIdentity` | ✅ |
| 診斷 | `MemoryFootprint`・`MemoryLogWriter` | ✅ 用它抓到洩漏 |

---

## 4. 進度地圖：Phase A–G 與 M0–M6

```mermaid
mindmap
  root((Backlog 60／66))
    A 可跑骨架 11／11 ✅
      1-2 CI 與注意力模型
      3-4 事件 tap 與 AX 焦點
      5-7 L0 格式化 合併 PII
      8-9 接進 menu bar 緊急停止
      10 真機 dogfood ✅ 通過
      10.5 可設定熱鍵 ✅ 通過
    B 智慧擷取引擎 13／15
      11-15 tile 幾何 dHash dirtyRects 金字塔 ✅
      16-17 接進 app 量測 harness ✅
      18 M0 真機驗收 ✅ idle 9%
      19-23 冷熱狀態機全整合 ✅
      23.5 CPU 優化 ⏸ 延後
      24 M1 真機驗收 ⬜ 待做
    C 局部 OCR 5／5 ✅
      25-26 ROI 映射 AX 優先
      27-28 sidecar OCR 與 pytest
      29 M2 真機驗收 ✅ 吞吐 18%
    D 記憶系統 6／7
      30-35 重建 環形 KNN 熱圖 ✅
      36 M3 真機驗收 ⬜ 8hr 磁碟量
    E 本地推理敘事 6／6 ✅
      37-41 階梯 fallback L2 vlm
      42 M4 真機驗收 ✅ 1373-2388ms
    F 雲端交棒 15／17 🔄
      43 沙箱威脅模型 ✅
      44-47 打包 閘門 契約 解析 ✅
      48-52 HUD 風險 沙箱 undo ✅
      53.1 XPC 骨架 ✅ 真機
      53.2 呼叫者驗簽 ✅ 真機
      53.3 sandbox profile ✅ 7 項全綠
      53.4 posix_spawn 執行端 ✅
      53.5 翻開執行開關 ✅ 真機 8／20
      53.6 UI 動作 A✅ B✅ C✅ 真機 9／3
      53.7 記憶體診斷 ✅ +151→+7 MB／hr
    G 隱私黑名單 4／5
      54-57 遮罩 黑名單 熱圖 ✅
      58 M6 真機驗收 ⬜
```

### 4.1 里程碑戰績表

| 里程碑 | 交付物 | 驗收步 | 狀態 | 實測數字 |
|---|---|---|---|---|
| **M0** 擷取引擎原型 | SCK + dirtyRects + Metal dHash + 注意力 | 18 | ✅ 真機通過 | idle CPU **9%**、operating 25% |
| **M1** 冷熱狀態機 | tile 四態 + 影片降頻 + foveation 排程 | 24 | ⬜ 待做 | 前置 23.5 CPU 優化已延後 |
| **M2** 局部 OCR | Vision ROI OCR + AX 文字優先 | 29 | ✅ 真機通過 | 像素吞吐 **18%**（目標 ≤20%）|
| **M2.5** L0 EventLog | deterministic 模板劇本 | 10 | ✅ 真機通過 | 操作時間機器可 dogfood |
| **M3** 記憶系統 | reference+delta + sqlite-vec + 熱圖 | 36 | ⬜ 待做 | 目標 8hr ≤ ~400MB |
| **M4** 本地推理 L1／L2 | FoundationModels 3B + 敘事階梯 | 42 | ✅ 真機通過 | 延遲 **1373–2388ms**、fallback 驗證通過 |
| **M5** 雲端交棒 | LiteLLM + Claude CU + HUD + 沙箱執行 | 53.1–53.7 | 🔄 **執行端已建成** | XPC ✅・sbpl 7 項全綠 ✅・記憶體修復 ✅・執行開關已翻開 |
| **M6** 隱私黑名單 | tile 遮罩 + 黑名單 + 熱圖隱私 | 58 | ⬜ 待做 | 目標密碼欄 100% 遮、黑名單 0 frame |

### 4.2 進度統計

```
步級   ███████████████████░░  60 / 66  （91%）
里程碑  ████████████░░░░░░░░   4 / 8   完全通過（M0 M2 M2.5 M4）+ M5 進行中
PR      ████████████████████  42 個已合併進 main
```

**剩下的 4 項**：`23.5` 擷取 CPU 優化（⏸ 延後）、`24` M1 驗收、`36` M3 驗收、`58` M6 驗收。

（`53.5` 與 `53.6-C` 已於 2026-09-03 對帳補上：兩者的真機驗收分別在 8／20 與 9／3
就通過了，只是文件沒跟上——53.5 那次一驗完就轉進記憶體診斷，沒有人回頭打勾。）

---

## 5. 資料流心智圖：一次交棒發生了什麼

### 5.1 本地感知鏈（全部在你的 Mac 上，已真機驗過）

```mermaid
flowchart LR
    A1["螢幕<br/>SCStream + dirtyRects"] --> B["Metal per-tile<br/>dHash 驗證"]
    A2["CGEventTap<br/>鍵鼠"] --> C
    A3["AX<br/>焦點元件 / 文字"] --> C
    B --> C["結構化事件 TileEvent<br/>有界緩衝"]
    C --> D["L0 事件日誌<br/>模板 + PII 前置遮罩"]
    D --> E["L1 ActionStep<br/>本地 3B FoundationModels"]
    E --> F["L2 段落摘要"]
    E --> G["MemoryStore 三層<br/>sqlite-vec"]
    F --> G
```

### 5.2 交棒鏈前半：出境閘門 → 雲端 → 提議

```mermaid
flowchart LR
    G["劇本 + 焦點小圖"] -->|"熱鍵 ⌃⌥⌘Space"| H["EnvelopeBuilder<br/>打包因果史"]
    H --> I{"① EgressGate<br/>出境閘門"}
    I -->|"PIPL 命中"| J["整包拒出<br/>只准走本地階"]
    I -->|"通過"| K["② LiteLLM Gateway<br/>預算熔斷"]
    K --> L["Claude computer-use<br/>SSE 串流"]
    L --> M["ComputerUseNormalizer<br/>→ ProposedAction"]
```

### 5.3 交棒鏈後半：風險閘 → 人工確認 → 沙箱執行

```mermaid
flowchart LR
    M["ProposedAction<br/>不可信提議"] --> N{"③ RiskClassifier +<br/>DangerousCommandDetector"}
    N -->|"high 風險"| O["接手 HUD<br/>強制人工確認"]
    N -->|"low + autoBounded"| P["自動核可<br/>有連續上限"]
    O --> Q["ApprovalToken 鑄造<br/>不過線"]
    P --> Q
    Q --> R["XPC service<br/>雙向 code-signing 驗證"]
    R --> S{"④ sandbox-exec sbpl<br/>posix_spawn argv 直呼"}
    S --> T["稽核四態<br/>attempt / executed<br/>notExecuted / blocked"]
    T --> U["UndoStack<br/>記錄反操作"]
    V["⌃⌥⌘. kill-switch"] -.->|"作廢整個世代 token"| Q
```

**目前的真實狀態**：整條鏈的程式碼都在，執行開關已於 2026-08-20 翻開。
驗證方式是一個**本地合成提議**走完全相同的路徑（風險分級 → HUD 人工確認 → token → 全部閘門 → XPC → sbpl）——
它不繞過任何閘門，只是把提議的來源從雲端換成本地，讓第一次真執行發生在完全受控的情況下。
**兩格還是假的**：「Claude computer-use」（真雲端 SSE 來源尚未接上，解析鏈用假來源驗過）
與 UI 動作（`willPerformUIActions` 旗標仍關著）。

---

## 6. 安全與隱私心智圖

```mermaid
mindmap
  root((信任邊界))
    縱深五層隱私
      1 L0 文字層 PIIMasker ✅ 真機驗過
      2 tile 遮罩層 SensitiveTileMask 🔒 step 58
      3 來源層 SCContentFilter 黑名單 🔒 step 58
      4 聚合層 熱圖只存權重 ✅
      5 出境層 EgressGate PIPL 拒出 🔒
    十條可測不變式
      I1 繞不過確認閘門 型別保證
      I2 high 風險必須人按
      I3 危險指令保守偏殺
      I4 無 shell 字串 只有 argv
      I5 路徑白名單 解 symlink
      I6 敏感不出境
      I7 kill-switch 作廢整世代
      I8 動作迴圈熔斷
      I9 每個提議都落稽核
      I10 gateway 預算與路由不變式
    翻開後的能力範圍 刻意極窄
      只有 shell 動作
      只有七個唯讀工具
        cat ls head tail wc grep find
        永遠不含 shell 本身
      只能寫沙箱工作目錄
      斷網 家目錄關閉
      秘密路徑另外 deny
      檔案動作明確拒絕
      每個動作仍需人工確認
    型別層設計
      ApprovalToken internal init 且不過線
        跨程序的值可以偽造
      ProposedAction 無整串 shell 欄位
      沒有驗證就不可以有執行能力
      誠實佔位一律 throw notWired
    威脅模型被實測更正
      R5 內嵌 XPC 必然同 uid
        買到的是程序隔離非權限降級
        真圍籬來自 sbpl
      R6 外部程序定址不到內嵌 service
        T7 主防線是 service 類型
    法遵
      台灣 PDPA
      上海團隊 PIPL 跨境條款
      敏感命中強制 local-only
```

---

## 7. 版本階梯心智圖：V1 → V4

```mermaid
mindmap
  root((版本階梯))
    V1 CoPartner 🔄 現行
      桌面 ambient 助理
      看螢幕 寫劇本 熱鍵交棒
      跳出電腦 0%
      2026-12 目標完成
    V2 Listen ⬜
      加耳朵與嘴巴
        全日音訊 本地轉錄
        生活劇本 螢幕+音訊統一時間軸
        Telegram 訊息閘道
        語音交棒
      36 steps 16-20 週
      跳出電腦 30%
    V3 Agent ⬜
      加手腳與主動性
        TopAppSkills 技能引擎
        heartbeat 主動巡檢
        手機手錶衛星 app
        信任階梯漸進自動化
      22 steps 18-24 週
      跳出電腦 70%
    V4 Omni ⬜
      穿戴優先最終形態
        眼鏡 墜飾 耳機
        即時耳語協助
        完整主人模型
      2028+ 硬體依賴 屆時調研
    貫穿架構 Hub-and-Satellites
      Mac mini M4 永遠是中樞
      手機手錶眼鏡都是衛星
      不存資料 不做重推理
      本地優先承諾每版都成立
```

---

## 8. 工程方法論（簡報最有料的一頁）

六條貫穿全案的原則，都是踩過坑換來的：

| 原則 | 內容 | 為什麼 |
|---|---|---|
| **可注入後端 + 誠實佔位** | 平台重活藏在 protocol 後，CI 用假後端驗邏輯；真後端沒接一律 `throw`，**絕不靜默假成功** | 開發代理跑在 Linux 容器、沒有 Mac，這是唯一能讓 92% 的工作在無真機下被驗證的辦法 |
| **安全不變式寫進型別** | `ApprovalToken` 的 `internal` init 讓「繞過閘門」在編譯層面不存在；`ProposedAction` 沒有整串 shell 欄位；`ApprovalToken` **不過 XPC**（跨程序的值可以偽造） | 防線不靠紀律、不靠 prompt，靠編譯器 |
| **先讓 endpoint 無害，再讓它有能力** | XPC service 先做成**沒有執行能力**的骨架，驗簽補上後才翻開開關；`willExecuteActions = true` 那一行**單獨成立一個 PR** | 翻開執行能力若混在一大包程式碼裡，沒有人（包括作者）能真的審完 |
| **build 綠 ≠ 真的編到了** | `canImport` 為 false 時整檔靜默略過、build 照樣綠 → `#if`／`#else` 兩側各放 `#warning` 取得**編譯期證據** | M4 的 FoundationModels 七項簽章，只有真機能當編譯器 |
| **驗證方式比被驗的東西重要** | 沙箱只測「擋得住」會得到假通過（deny-default 下什麼都跑不起來）→ **成對驗證**，負向結果**依賴**正向基準；基準沒過就全部標「無效」而非「通過」 | 一個測不出東西的測試，比沒有測試更危險 |
| **不猜、拒收、明講慣例** | parser 遇未知 tool 就拒收；修飾鍵無法表示就 `throw`；`KeyChord` 認不得就整個丟出錯誤 | 「認得幾個算幾個」會讓 HUD 顯示的與實際按下的不同 |

### 真機 dogfood 抓到、CI 永遠測不到的 bug

1. **FOCUS 狂刷** — 終端機每輸出一個字就被判定換視窗。*根因*：焦點追蹤誤用 AX `value`（欄位**內容**）當視窗識別。後來又抓到同源的另外三類（會變的標題／「讀不到」／兩個不同來源的欄位當身分），四條回歸測試釘住。
   **教訓：邏輯正確、測試也過——錯在真機餵給它的資料。**
2. **OCR 截整螢幕** — 混入選單列和其他 app 文字，吞吐等同沒優化。*修*：依 AX 焦點框裁切 → **18%**。
3. **Vision bbox 左下原點** — 與螢幕座標慣例相反，沿用會讓摘要**上下顛倒**。
4. **稽核不誠實** — 被閘門擋下的動作原本留下**零痕跡**；執行未成功時原本記成已執行。*修*：改成 attempt／executed／notExecuted／blocked 四態。
5. **記憶體線性成長** — 沒開觀察、只是讓 app 開著就會跳系統告警。七輪診斷後定位：`AsyncStream<TileEvent>` 沒指定 buffering policy（無上限），唯一的消費者是 `@MainActor` 計數器，每個事件跳一次 MainActor、產生端不會等它。*修*：`.bufferingNewest(64)` → **+151 MB/小時 降到 +7 MB/小時**。

### 診斷過程本身推翻了三個中途結論

一次性暖機被整體斜率攤成成長率／階段落差被攤成成長率／「ratchet 確認」其實是**量測時機**造成的假象（停止後 1–5 分鐘記憶體根本還沒開始掉，真正的落定點在 30 分鐘）。
每一次都是同一種錯誤：**一個看起來像資料的猜測，比「不知道」更糟。**

---

## 9. 關鍵路徑：M5 還剩什麼

```mermaid
flowchart LR
    A["✅ 已完成<br/>XPC 骨架 · 雙向驗簽 · sbpl 8 項全綠<br/>第一次真執行 · 第一次真的動電腦"] --> C["接上真雲端 SSE 來源<br/>LiteLLM → Claude CU"]
    C --> D["M5 完整驗收<br/>對照 I1–I10 逐項勾"]
    E["驗收清單"] -.-> D
    E1["危險指令被攔 · 不可自動核准"] -.-> E
    E2["kill-switch 全鏈斷"] -.-> E
    E3["越界寫入被 deny"] -.-> E
    E4["LiteLLM 預算熔斷"] -.-> E
    E5["接手品質 · Claude 續寫而非貼說明"] -.-> E
```

**M5 之後的路線**：M3 真 vec0（step 36，盲寫風險低但要跑 8hr 驗磁碟量）→ M1 擷取 CPU 優化 + 影片驗收（23.5 + 24）→ M6 隱私最終審查（58）→ V1 收官 → V2 Listen 開工。

**兩件已知但刻意未處理的**：
- **L1 會編故事**：終端機標題 `CoPartner — -zsh — 100×34` 被 3B 腦補成「與 CoPartner 進行視訊會議」。指令已明寫禁止臆測，3B 壓不住。這是 L1 品質調校，與 M5 是兩條線。
- **同一個 app 內換視窗仍會記 FOCUS**：只有 CI 測試蓋到，下次 dogfood 開兩個終端機視窗切一下就能補驗。

---

## 10. 文件地圖

```mermaid
mindmap
  root((docs/))
    本文件 project-mindmap.md
      視覺入口 + 進度全景
    planning 規劃與進度
      implementation-backlog.md
        58 步 TDD 進度單一事實來源
        step 53 已展開為 53.1-53.7
      realmachine-runbook.md
        六個 🔒 里程碑逐步 dogfood 清單
      session-handoff.md
        可獨立運作的交接包 900+ 行
      assistant-evolution-plan.md
        V2 V3 V4 版本演化總規劃
      dev-execution-plan.md
        模型分工 時程 費用
      ppt-material.md
        簡報素材與講稿
      phase-a-review.md step18-dogfood.md
        階段回顧與真機紀錄
    design 主設計
      v1_full-design.md 完整系統設計
      v2_smart-capture-engine.md 智慧擷取
      v2.1_action-script-narrator.md 劇本與交棒
      sandbox-threat-model.md I1-I10 不變式
    architecture 架構
      overview.md 模組相依
      data-flow.md 接手時序
      process-topology.md 程序與信任邊界
    adr 七則決策紀錄
      0002 ScreenCaptureKit
      0003 foveated dirty-region
      0004 Action Script Narrator
      0005 混合本地雲端路由
      0006 點擊驅動注意力升級
      0007 本地優先分層推理
    privacy
      data-classification.md 資料分類矩陣
    assets 簡報素材
      deck 20 頁 pptx 與產生器
      panorama.html 單頁視覺版全景
      diagrams 十張圖的 SVG 與 PNG
```

---

## 11. 維護方式

這份文件是**衍生視圖**，不是事實來源。更新順序永遠是：

1. 先改 `docs/planning/implementation-backlog.md` 的**進度總覽表 + 該 step 詳細章節**（兩處都要——過去多次只改一處造成漂移）。
2. 真機驗收結果同步進 `docs/planning/realmachine-runbook.md` 的對應里程碑節，脈絡進 `session-handoff.md`。
3. 里程碑翻牌時，回來更新本文件的 §1／§4／§9，以及 `README.md`／`README.en.md`／`CHANGELOG.md`。
4. 圖改了要重新匯出 `docs/assets/diagrams/`（方法見該目錄 README）；`docs/assets/panorama.html` 與 `docs/assets/deck/gen.js` 裡的數字都是硬寫的，一併更新。
