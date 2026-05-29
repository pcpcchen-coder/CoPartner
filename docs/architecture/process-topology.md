# 程序拓樸

| 程序 | 啟動 | 沙箱 | 權限 |
|---|---|---|---|
| CoPartner.app（menu bar 主程序） | 使用者登入 | 否（需跨程序 AX/CGEvent） | Screen Recording / Accessibility / Input Monitoring |
| CaptureEngine（可內嵌主程序或獨立 agent） | launchd LaunchAgent | 否 | 同上 |
| ScriptNarrator（FoundationModels） | 內嵌 | — | 需開啟 Apple Intelligence |
| sidecar（Python MLX） | launchd / dev-run.sh | 否 | GPU/ANE |
| LiteLLM Gateway | Docker | 容器隔離 | 出網 only |
| ActionExecutor | sandboxed XPC | 是 | 限定範圍 |

> macOS 26.1+ TCC 陷阱：未打包成簽章 .app bundle 的執行檔不會出現在權限清單。
