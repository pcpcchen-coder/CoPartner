#!/usr/bin/env bash
set -euo pipefail
# 安裝開發依賴並產生 Xcode 專案
command -v brew >/dev/null || { echo "請先安裝 Homebrew"; exit 1; }
command -v xcodegen >/dev/null || brew install xcodegen
command -v uv >/dev/null || brew install uv
( cd apps/CoPartner && xcodegen generate )
echo "✅ 完成。用 Xcode 開啟 apps/CoPartner/CoPartner.xcodeproj"
