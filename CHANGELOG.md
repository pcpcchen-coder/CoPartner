# Changelog

本專案的所有重要變更皆記錄於此。格式參考 Keep a Changelog，版本遵循語意化版本。

## [Unreleased]
### Added
- ADR-0007：本地優先的分層推理階梯與雲端升級（小範圍辨識留本地、大變動才送雲端；RoutingSignal / InferenceTier / EscalationPolicy + 單元測試）。
- ADR-0006：點擊驅動的注意力升級（事件加權注意力能量模型，AttentionModel）。
- 初始 repo 骨架與完整設計文件（V1 / V2 / V2.1）。
- macOS-first 專案結構：CoPartnerKit Swift package、SwiftUI menu bar app 骨架、
  Python 推理 sidecar、LiteLLM 基礎設施、CI、ADR。
