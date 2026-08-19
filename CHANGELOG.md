# Changelog

本專案的所有重要變更皆記錄於此。格式參考 Keep a Changelog，版本遵循語意化版本。

## [Unreleased]

### 真機里程碑
- **M5 接手（進行中）**：computer-use 契約對齊、SSE 傳輸、接手 HUD、
  執行端 XPC 骨架與雙向 code-signing 驗證、`sandbox-exec` profile 成對驗證（7 項全綠）。
  🔒 剩 `posix_spawn` 接線與翻開執行開關。
- **M4 本地敘事** ✅ 真機通過：FoundationModels 3B，1373–2388ms／step，
  關閉 Apple Intelligence 自動降級規則式且不中斷。
- **M2 局部 OCR** ✅ 真機通過：改用 macOS Vision（不再依賴 sidecar），吞吐 18%（目標 ≤20%）。
- **Phase A 操作時間機器** ✅ 真機通過。

### Added
- 安全邊界的**可執行驗證**：`scripts/sandbox-verify.sh`（沙箱成對測試，
  負向結果依賴正向基準，測不出東西時報「無效」而非「通過」）、
  `scripts/xpc-probe.swift`（從外部程序實測拒絕路徑）。
- 架構圖改用 Mermaid（`docs/architecture/`）：模組相依、程序拓樸、資料流、
  接手時序、信任邊界。純文字可 diff，GitHub 直接算圖。
- 英文 `README.en.md`。

### Changed
- 威脅模型 §6 從草稿升格為**已驗證**，並更正一個錯誤假設：內嵌 XPC service
  **必然與主 app 同 uid**（實測 euid 501），因此那道邊界買到的是程序隔離而非權限降級；
  真正的圍籬來自 sbpl profile。記為殘餘風險 R5。
- 威脅模型 R6 由實測解答：外部程序**定址不到**內嵌 XPC service，
  因此 T7 主防線是 service 的類型而非 code-signing requirement。
- backlog step 53 展開為 53.1–53.6——原本只是一句「真機驗收」，
  但前置的執行端根本還不存在。

### Fixed
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
