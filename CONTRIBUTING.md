# 開發指南

## 分支策略
- `main`：穩定、可建置。
- `feat/<milestone>-<topic>`：功能分支，對應 roadmap milestone（如 `feat/m0-capture-prototype`）。

## Commit 慣例
採用 Conventional Commits：`feat:` `fix:` `docs:` `refactor:` `test:` `chore:`。

## 架構決策
任何影響架構的決定，請在 `docs/adr/` 新增一份 ADR（複製 0001 範本編號遞增）。

## macOS 權限
本專案需要 Screen Recording / Accessibility / Input Monitoring TCC 權限，
且**必須打包為簽章 .app bundle** 才能在 macOS 26.1+ 的權限清單中被授權。
開發時先跑 `scripts/permissions-check.sh`。

## 程式風格
- Swift：swift-format 預設。
- Python：ruff + black。
