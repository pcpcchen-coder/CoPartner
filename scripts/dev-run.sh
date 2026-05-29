#!/usr/bin/env bash
set -euo pipefail
# 一鍵啟動本地依賴（sidecar + LiteLLM），app 請於 Xcode 執行
( cd sidecar && uv run copartner-sidecar ) &
( cd infra/litellm && docker compose up -d )
echo "✅ sidecar (:8765) 與 LiteLLM (:4000) 已啟動"
