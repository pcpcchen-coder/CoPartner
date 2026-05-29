#!/usr/bin/env bash
set -euo pipefail
# 檢查 / 引導 macOS TCC 權限。注意：必須以簽章 .app bundle 執行才會出現在權限清單（macOS 26.1+）。
echo "請於『系統設定 > 隱私權與安全性』確認下列權限已授予 CoPartner.app："
echo "  1) 螢幕與系統音訊錄製 (Screen Recording)"
echo "  2) 輔助使用 (Accessibility)"
echo "  3) 輸入監控 (Input Monitoring)"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture" || true
