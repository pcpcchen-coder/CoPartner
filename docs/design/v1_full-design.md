# macOS Ambient AI Assistant — 完整技術設計文件 V1 (Mac Mini M4 / Apple Silicon)

> 註：本文件為最初的完整設計（定頻擷取基線）。智慧擷取引擎的升級見 v2，操作劇本與交棒機制見 v2.1。本文件保留作為平台 API、混合模型、隱私合規、沙箱、路線圖的基礎參考。

## TL;DR

- **架構**：Swift 原生感知/動作層 + Python 推理協調層 + LiteLLM Gateway 雙模型路由。本地以 ScreenCaptureKit + AXUIElement + Vision OCR 形成低耗能觀察管線；雲端以 Claude Sonnet 4.6 / Opus 4.7 的 `computer-use-2025-11-24` 工具承擔規劃；以 macOS 原生 hotkey（Sindre Sorhus 的 `KeyboardShortcuts` SPM）觸發介入。
- **隱私邊界**：本地 Apple Foundation Models 3B（macOS 26 Tahoe `FoundationModels` framework）+ Qwen2.5-VL-7B (MLX-VLM) 負責 PII 偵測、敏感視窗黑名單、意圖分類；只有遮罩後的事件可上雲。Taiwan PDPA（新設個人資料保護委員會 PDPC，2025-11-11 修法公布）與中國 PIPL Article 38（CAC 主管，2026-01-01 生效之認證辦法）同時適用。
- **可行性**：Mac Mini M4 24GB（閒置 2.6-2.7W、壓力測試峰值 62.5W、穩定 57-58W）可支撐 1-5 FPS 擷取 + 7B VLM 本地推理 + 雲端 Claude 介入；個人 side-project 節奏（5-10 hrs/週）約 6-9 個月可達 M5「完整代理迴圈 + MCP 整合」。

## Key Findings

1. **ScreenCaptureKit 是唯一推薦的螢幕擷取 API**（macOS 12.3+），支援 IOSurface/Metal 零拷貝、async 流式；CGWindowList 與 AVCaptureScreenInput 自 macOS 13 起已棄用或不建議。
2. **Claude Computer Use 已進入 4.x 世代**：beta header `computer-use-2025-11-24`（Opus 4.7 / 4.6 / Sonnet 4.6 / Opus 4.5），新增 `zoom`，Opus 4.7 高解析度 2576px / 3.75MP；官方 reference 仍是 Linux X11/Xvfb Docker 容器，macOS 必須自行實作工具端對應到 CGEvent / AX。
3. **本地 VLM 在 M4 上可用**：Qwen2.5-VL-7B (MLX 8-bit) 約 8.5 GB RAM、25-35 tok/s；OCR 仍以 Apple Vision `VNRecognizeTextRequest` 最快（zh-Hant + en）。
4. **Apple Foundation Models framework**（macOS 26 Tahoe，2025-09-29 開放）：3B on-device LLM、Swift API、`@Generable` macro、guided generation、tool calling、LoRA adapter — 是 PII 過濾與輕量結構化輸出的首選。
5. **Rewind.ai 已停服**：Limitless 於 2025-12-05 被 Meta 收購，screen/audio capture 於 2025-12-19 停用；開源 screenpipe（YC S26，MIT）接手 — accessibility-tree-first + OCR fallback + 內建 MCP server 的架構直接可借鑑。
6. **路由經濟學**：Sonnet 4.6 $3/$15 per Mtok 主力，Opus 4.7 $5/$25 留給長時程；prompt caching（命中 0.1×、5-min TTL write 1.25×）+ batch API（50% 折扣）可顯著降本。
7. **法規硬約束**：使用者位於台灣 + 有上海團隊，任何包含上海同事螢幕內容上雲都觸發 PIPL Article 38（CAC 安全評估 / SCC / PIP 認證三選一）。

## A. 系統架構

```
[感知層] ScreenCaptureKit / AXUIElement / CGEventTap / NSPasteboard
   │ NSXPCConnection
[觀察緩衝層] L1 RingBuffer(RAM 5min) / L2 SQLite+sqlite-vec(1hr) / L3 SQLCipher(30d)
   │ 隱私閘門: app blacklist + Presidio + FM 3B
[本地推理層] Apple FoundationModels 3B / Qwen2.5-VL-7B-MLX / Vision OCR
   │
[路由層] LiteLLM Gateway（presidio guardrail / 複雜度路由 / 預算閘門）+ MCP Client
   │ HTTPS (ZDR endpoint)
═══ 信任邊界 ═══
[雲端推理層] claude-sonnet-4-6 / claude-opus-4-7 + computer_20251124 + bash + text_editor
   │
[執行層] CGEvent / AXUIElementSetAttributeValue / NSAppleScript / Shortcuts / sandboxed shell
   │ Undo stack（APFS localsnapshot / git stash）+ rate limiter + dangerous pattern detector
橫切：加密 audit log（libsodium secretstream）/ TCC 監測 / dead-man's switch
```

程序拓樸：menu bar app（SMAppService.mainApp，TCC 權限、hotkey、設定）；perception agent（LaunchAgent，SCK+AX walker）；reasoning（Python，mlx-vlm + FM bridge + LiteLLM client）；executor（隔離 `_ambient` user，XPC on-demand）；litellm-gateway（Docker）。

## B. macOS 平台技術細節

### B.1 螢幕擷取
ScreenCaptureKit 是唯一 Apple 持續維護的擷取 API。差分擷取策略：SCStream `minimumFrameInterval` 設 2 FPS 上限、收到 CMSampleBuffer 後算 dHash（Metal）、與上張 hamming distance < 5 丟棄、焦點變更強制 capture。注意 macOS 26.1 regression：plain executable 不再顯示於螢幕錄製權限清單，必須打包為 .app bundle。

### B.2 Accessibility API
由上而下 `AXUIElementCreateApplication(pid)` BFS 整棵 UI tree；由下而上 `AXUIElementCreateSystemWide()` + `kAXFocusedUIElementAttribute`（< 5ms）。推薦 wrapper `AXorcist`。App Sandbox 與 AX 不相容，必須關閉 sandbox。

### B.3 輸入監聽
用 CGEventTap（Input Monitoring 權限，sandbox/App Store 友善）而非 NSEvent global monitor（需 Accessibility 權限）。`.listenOnly`、處理 `kCGEventTapDisabledByTimeout`、Secure Keyboard Entry 由 OS 自動 mute。

### B.4 GUI 自動化（寫入）優先序
1) Shortcuts.app via x-callback-url（最安全、可審計，Tahoe 起可 tap Apple Intelligence）2) AXUIElementSetAttributeValue 寫 text field（比模擬鍵盤快 100×）3) NSAppleScript 4) CGEvent.post（最後手段）。

### B.5 全域熱鍵
`KeyboardShortcuts`（Sindre Sorhus，SPM、sandbox/App Store 相容、SwiftUI Recorder）。建議：主介入 ⌃⌥⌘Space、緊急停止 ⌃⌥⌘.、觀察開關 ⌃⌥⌘O。

### B.6 TCC 權限
Screen Recording / Accessibility / Input Monitoring / Automation / Full Disk Access。引導 UX：onboarding 列缺項 + URL scheme 直跳設定頁。

### B.7 背景常駐
SMAppService（macOS 13+）取代 SMJobBless。注意 MDM 安裝可能 Error 108，手動 install 較穩。

### B.8 Apple Silicon 優化
M4 16-core NE 38 TOPS；MLX 比 llama.cpp Metal 快 21-87%；Metal Performance Shaders 做 dHash；VideoToolbox H.265 硬編。

### B.9 macOS Tahoe (26) 新 API
FoundationModels framework（3B on-device、`@Generable`、tool calling）；Shortcuts ↔ Apple Intelligence；Live Activities on Mac；Spotlight Action API。

## C. 本地模型選型（Mac Mini M4 24GB）

| 模型 | 量化 | RAM | 用途 |
|---|---|---|---|
| Apple FM 3B | Apple QAT | ~1.5GB | PII / 結構化 / 意圖 |
| Qwen2.5-VL-7B | MLX 8-bit | ~8.5GB | 螢幕語意 / UI agent |
| Qwen2.5-VL-3B | MLX 4-bit | ~2.5GB | 輕量分類 |

結論：24GB 上長駐 Qwen2.5-VL-7B + FM 3B，30B+ 留雲端。OCR 預設 Vision `VNRecognizeTextRequest`（zh-Hant+en）；fallback PaddleOCR / VLM。Python bridge 用 ocrmac。

## D. 雲端 Claude 整合

### D.1 Computer Use（2026-05）
beta header `computer-use-2025-11-24`；工具 `computer_20251124` + `bash_20250124` + `text_editor_20250728`；新增 zoom；system prompt overhead 466-499 tokens；官方 demo 為 Docker Linux X11/Xvfb，macOS 須自行把動作接到 CGEvent/AX；Opus 4.7 最高 2576px/3.75MP；建議申請 ZDR。

### D.2 路由與成本
含不可遮罩 PII → local；簡單動作（信心高、≤2 動作）→ local；長時程/>50K tokens → Opus；其餘 → Sonnet。優化：prompt caching 5-min TTL、batch API 50%、effort parameter。

### D.3 LiteLLM 配置
見 infra/litellm/config.yaml。presidio pre-call guardrail、cost-based routing、fallbacks、max_budget。

### D.4 MCP
Sonnet 4.6+ 原生 MCP client。建議掛 filesystem / github / screenpipe（SQL 查 screen history）/ 自家 EMS API。MCP 2025-12 捐 Linux Foundation；pin protocol version。

## E. 觀察緩衝與記憶

三層：L1 Hot（RAM 5min）/ L2 Warm（SQLite+sqlite-vec 1hr）/ L3 Cold（SQLCipher 30d）。事件壓縮：raw frame → dHash 過濾 → Vision OCR → +AX focused +鍵鼠 → StructuredEvent → 60s batch FM 摘要+embedding → 5min Qwen high-level summary。向量庫選 sqlite-vec。隱私事件兩道閘門：app 黑名單（SCStream 直接排除）+ 內容層 PII（Presidio + FM 3B）。資源：磁碟約 3GB/月。

## F. 觸發與介入流程

時序：⌃⌥⌘Space → XPC snapshot → AX focused + SCStream frame + 30s 事件 → ContextEnvelope → presidio → LiteLLM → 首 chunk ~150ms → HUD 建議 → tool_use（半自動確認 / 全自動執行）。介入模式：Suggest / Confirm-each / Auto-bounded / Full-auto（不建議）。Undo：git stash / APFS snapshot / AX tree snapshot。HITL HUD 顯示推測任務 + 下一步 + 信心度 + Approve/Skip/Stop。

## G. 隱私與安全

資料分類矩陣（絕對不出本機 / 遮罩後可上雲 / 可直接上雲 / 業務敏感）。加密：SQLCipher（key 存 Keychain）、audit log libsodium secretstream。Dead-man's switch 三層：hotkey / heartbeat / budget。

## H. 安全沙箱與動作執行

Shell 沙箱：專用 `_ambient` unprivileged user + sandbox-exec sbpl profile（限 network/exec/file write）。危險動作偵測（rm -rf / sudo / fork bomb / dd / curl|sh / git push -f / defaults write）→ 強制 confirm-each。速率限制與 loop 偵測。

## I. 實作技術棧

Swift/SwiftUI（menu bar + perception）、Python 3.12（reasoning + MLX + LiteLLM）、Rust（可選後期）。框架：MenuBarExtra、KeyboardShortcuts、AXorcist、mlx-lm/mlx-vlm、LiteLLM、sqlite-vec、NSXPCConnection。參考開源：screenpipe、Open Interpreter、Anthropic computer-use-demo、Self-Operating Computer、AXorcist、macOSpilot。

## J. 路線圖（5-10 hrs/週）

- M1 純被動觀察（4 週）
- M2 本地 VLM 意圖推測（3 週）
- M3 熱鍵 + Claude 介入（純建議）（3 週）
- M4 GUI 自動化 + 安全沙箱（4 週）
- M5 完整代理迴圈 + MCP + 稽核（4 週）
- M6 個人化學習與 workflow templates（持續）

## K. 成本與硬體

雲端：輕度 ~$10/月、中度 ~$120/月、重度 ~$450/月（prompt caching 可省 60-90%）。硬體：24GB 為實用最低，32GB 為「本地跑 30B 替代雲端」合理投資；不需 eGPU。電力：24/7 平均 ~10-15W。

## L. 風險、限制、倫理

macOS 更新破壞 API（每年 WWDC 變動）；App Store 政策（權限全違反 sandbox → Developer ID 分發）；共用電腦/家人倫理；跨境傳輸（PDPA + PIPL）；AI 誤判風險矩陣（依可逆性分級強制確認）。

## M. 同類產品比較

Rewind→Limitless（Meta 收購停服）、Cluely（overlay 作弊工具，倫理立場不同）、Microsoft Recall（default-on 全紀錄的政治風險警示）、Apple Intelligence（積極使用做 PII/摘要）、Self-Operating Computer、Claude Computer Use（官方 Linux demo）、Open Interpreter、screenpipe（架構幾乎直接可借鑑）。
