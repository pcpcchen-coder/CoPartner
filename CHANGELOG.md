# Changelog

本專案的所有重要變更皆記錄於此。格式參考 Keep a Changelog，版本遵循語意化版本。

## [Unreleased]

### 真機里程碑
- **M5 接手（進行中）**：computer-use 契約對齊、SSE 傳輸、接手 HUD、
  執行端 XPC 骨架與雙向 code-signing 驗證、`sandbox-exec` profile 成對驗證（8 項全綠）、
  `posix_spawn` 真執行接線。
  - **shell 執行開關已翻開**（2026-08-20）：門禁清單逐項打勾後，app 第一次真的
    執行了沙箱內的命令（`cat` 讀回檔案內容，UUID 對得上）。
  - **UI 執行能力已翻開**（2026-09-03）：按「UI 測試」→ HUD 人工確認 → 畫面真的捲動。
    **這是 CoPartner 第一次動使用者的電腦。**
  - 🔒 剩真雲端 SSE 來源。
- **M4 本地敘事** ✅ 真機通過：FoundationModels 3B，1373–2388ms／step，
  關閉 Apple Intelligence 自動降級規則式且不中斷。
- **M2 局部 OCR** ✅ 真機通過：改用 macOS Vision（不再依賴 sidecar），吞吐 18%（目標 ≤20%）。
- **Phase A 操作時間機器** ✅ 真機通過。

### Added
- **`docs/project-mindmap.md`**：專案心智圖與進度全景——三大理念、模組×檔案×狀態、
  Phase A–G 進度地圖、本地感知鏈與交棒四道閘、安全隱私邊界、V1→V4 版本階梯、
  工程方法論、M5 關鍵路徑、文件地圖。十張 Mermaid 圖皆已實際渲染驗證。
- **`docs/README.md`**：全部文件索引與維護規則（含「進度總覽表與 step 詳細章節兩處都要改」
  這條，過去多次只改一處造成漂移）。
- **`docs/planning/ppt-material.md`**：簡報素材——20 頁投影片大綱，每頁含版面建議／
  板書內容／講稿，另附場合裁切（5/15/30 分鐘）、可引用數字表、Q&A 預備。
- **`docs/assets/diagrams/`**：十張圖的 SVG + 2x PNG 匯出，供 PowerPoint / Keynote 直用。
- **`docs/assets/deck/`**：依 `ppt-material.md` 大綱做出的 **20 頁 .pptx**（16:9，每頁附講者備忘稿），
  含產生器 `gen.js`——deck 不手改，改產生器後重跑。關鍵視覺原生繪製（foveation 場、
  66 格 tile 進度陣列、版本階梯），不貼縮小後看不清的心智圖 PNG。
- **`docs/assets/panorama.html`**：單頁視覺版全景——里程碑燈號、Phase A–G tile 進度圖、
  交棒四道閘、翻開執行能力後的允許／拒絕對照、工程方法論、真機教訓、記憶體診斷、
  版本階梯、誠實風險清單、數字附錄。單一檔案、無需建置、淺色深色自動跟隨系統，
  瀏覽器直接開即可投影或截圖。同樣內容另發佈了一份線上版。
- 安全邊界的**可執行驗證**：`scripts/sandbox-verify.sh`（沙箱成對測試，
  負向結果依賴正向基準，測不出東西時報「無效」而非「通過」）、
  `scripts/xpc-probe.swift`（從外部程序實測拒絕路徑）。
- 架構圖改用 Mermaid（`docs/architecture/`）：模組相依、程序拓樸、資料流、
  接手時序、信任邊界。純文字可 diff，GitHub 直接算圖。
- 英文 `README.en.md`。
- **UI 執行端（step 53.6）**：`UIActionGate`（沒有輔助使用權限一定拒絕——沒有它時
  `CGEvent.post` 不會失敗、不會丟錯，就是靜默什麼都不做）、`VirtualKeyMap`
  （鍵名→鍵碼，用 Carbon 具名常數；寫死數字錯一個的後果不是「按不到」是「按到別的鍵」）、
  `ScreenCoordinateMapper`（算式裡沒有 backingScale——化成比例後縮放與 Retina 同時被約掉；
  越界拒絕不夾邊）、`TakeoverPolicyGuard`（autoBounded ＋ UI 控制權 ⟹ 降為逐一確認）。
  驗收入口「UI 乾跑」印出落點與**那個位置上的 AX 元件**——座標算錯不會報錯，
  那一行是唯一能在事前看出差別的東西。
- **執行能力（step 53.5）**：`ExecutorService.willExecuteActions` 翻成 `true`。
  能力範圍刻意遠比「能執行指令」窄——只有 `shell`、只有本地固定表裡七個唯讀工具
  （cat/ls/head/tail/wc/grep/find，**永遠不含 shell 本身**）、只能寫沙箱工作目錄、
  斷網、家目錄關閉、秘密路徑另外 deny、檔案動作明確拒絕，而且每個動作仍需
  本地風險分級與 HUD 人工確認。翻回 `false` 是出事時的第一動作，只需改一行。
- 除錯入口「執行測試」：送一個**本地合成提議**走完整條接手鏈（風險分級 → HUD 確認 →
  token → 全部閘門 → XPC → sbpl）。不是繞過閘門，只是把提議來源從雲端換成本地——
  讓第一次真執行發生在完全受控的情況下，而不是在第一次接上雲端時。
  驗收判定條件是「stdout 裡有那串隨機標記」，不是 `didExecute == true`：
  沙箱擋掉讀取時 `cat` 照樣會結束、`didExecute` 照樣為真，stdout 卻是空的。

### Changed
- 威脅模型 §6 從草稿升格為**已驗證**，並更正一個錯誤假設：內嵌 XPC service
  **必然與主 app 同 uid**（實測 euid 501），因此那道邊界買到的是程序隔離而非權限降級；
  真正的圍籬來自 sbpl profile。記為殘餘風險 R5。
- 威脅模型 R6 由實測解答：外部程序**定址不到**內嵌 XPC service，
  因此 T7 主防線是 service 的類型而非 code-signing requirement。
- backlog step 53 展開為 53.1–53.7——原本只是一句「真機驗收」，
  但前置的執行端根本還不存在。
- **進度文件對帳**：backlog 進度總覽表補上統計摘要，並修正三處與現實脫節的標記——
  step 42（詳細章節與 commit 都寫著 M4 真機通過，表格停在 ⬜）、step 53（表格仍是單一列，
  實際已展開成 53.1–53.7 且多數真機通過）、step 23.5（「延後」與「未開始」原本共用 ⬜，
  分出 ⏸）；圖例補完（原本 ⬜/🔄 那列的意義欄是空的）。runbook 的 M5 節與抬頭同步到現況，
  `git pull` 指令由舊工作分支改為 `main`。README.en.md 的執行端切片表同步
  （開關已於 2026-08-20 翻開，原表仍寫「not yet」）。

### Fixed
- **`scroll` 動作沒有座標**（真機第一次 UI 執行時發現）。捲動事件是送到「某個位置底下
  的視窗」的，沒有座標就只能落在游標當下的地方；而 `ComputerUseNormalizer` 一直把真 API
  送來的 `coordinate` 丟掉。真雲端接上後，Claude 看著截圖決定要捲哪一塊，我們會捲到
  游標剛好停著的地方——**而且不會報錯**。`Kind.scroll` 補上座標，缺欄位一律 throw
  而不是退回「就捲游標那裡」（那是猜，而猜出來的動作與使用者核准的不是同一件事）。
- **記憶體：觀察中的線性成長**（真機 +151 MB/小時 → +7 MB/小時）。成因是
  `CaptureEngine` 的 `AsyncStream<TileEvent>` 沒有指定 buffering policy（無上限），
  而它唯一的消費者是一個 `@MainActor` 計數器——每個事件都要跳一次 MainActor，
  產生端不會等它。同一條管線上游的 `SCKFrameProducer` 早就用了 `.bufferingNewest(2)`。
  改成 `.bufferingNewest(64)`，並把丟棄數顯示在選單上（靜默丟事件會讓「消費端塞車」
  這個訊號消失，而那正是診斷要找的東西）。
- `FocusChangeTracker` 四類同源 bug：拿欄位內容 / 會變的標題 / 「讀不到」/
  兩個不同來源的欄位當視窗身分。四條回歸測試釘住。
- `SbplProfileBuilder` 路徑未跳脫（安全設定裡的注入面）、未解符號連結
  （給 `/tmp/x` 的規則對 `/private/tmp/x` 永遠不匹配，而 profile 看起來完全正常）。
- 稽核紀錄不誠實：被閘門擋下的動作原本留下**零痕跡**；執行未成功時原本記成
  已執行。改為 attempt / executed / notExecuted / blocked 四態。

### Added（既有）
- 版本演化總規劃 `docs/planning/assistant-evolution-plan.md`：V2 Listen（全日音訊＋訊息閘道）→ V3 Agent（TopAppSkills 技能引擎＋主動性＋隨身衛星）→ V4 Omni（穿戴優先最終形態）；Hub-and-Satellites 架構、生活劇本資料模型、隱私/法律原則、V2 完整 36 步 TDD backlog、V3 22 步、成本與時程估算。
- 開發執行計畫 `docs/planning/dev-execution-plan.md`：模型分工（Sonnet 5 / Opus 4.8 / Fable 5）、時程與訂閱費用評估。
- 實作待辦清單 `docs/planning/implementation-backlog.md`：58 個 step 的 TDD backlog，採「可跑骨架優先」順序，區分 CI 可驗證（✅）與需真機驗證（🔒）。
- ADR-0007：本地優先的分層推理階梯與雲端升級（小範圍辨識留本地、大變動才送雲端；RoutingSignal / InferenceTier / EscalationPolicy + 單元測試）。
- ADR-0006：點擊驅動的注意力升級（事件加權注意力能量模型，AttentionModel）。
- 初始 repo 骨架與完整設計文件（V1 / V2 / V2.1）。
- macOS-first 專案結構：CoPartnerKit Swift package、SwiftUI menu bar app 骨架、
  Python 推理 sidecar、LiteLLM 基礎設施、CI、ADR。
