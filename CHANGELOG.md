# Changelog

本專案的所有重要變更皆記錄於此。格式參考 Keep a Changelog，版本遵循語意化版本。

## [Unreleased]
### Added
- 開發執行計畫 `docs/planning/dev-execution-plan.md`：模型分工（Sonnet 5 / Opus 4.8 / Fable 5）、時程與訂閱費用評估。
- 實作待辦清單 `docs/planning/implementation-backlog.md`：58 個 step 的 TDD backlog，採「可跑骨架優先」順序，區分 CI 可驗證（✅）與需真機驗證（🔒）。
- ADR-0007：本地優先的分層推理階梯與雲端升級（小範圍辨識留本地、大變動才送雲端；RoutingSignal / InferenceTier / EscalationPolicy + 單元測試）。
- ADR-0006：點擊驅動的注意力升級（事件加權注意力能量模型，AttentionModel）。
- 初始 repo 骨架與完整設計文件（V1 / V2 / V2.1）。
- macOS-first 專案結構：CoPartnerKit Swift package、SwiftUI menu bar app 骨架、
  Python 推理 sidecar、LiteLLM 基礎設施、CI、ADR。
