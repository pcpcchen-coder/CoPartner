# CoPartner

> 一個在 macOS 上持續觀察你的操作、用本地模型把行為寫成「操作劇本」、並在你按下熱鍵時由雲端大模型接手完成任務的 **Ambient AI Assistant**。

**首要目標平台**：Mac Mini M4 / Apple Silicon，macOS 26 Tahoe（向下相容 Sequoia 15 為次要目標）。

## 這是什麼

CoPartner 由三個核心理念組成：

1. **看得省（Smart Capture Engine）** — 不做定頻全畫面截圖，改用 foveated + dirty-region 擷取：滑鼠/焦點區高解析高頻，周邊低解析低頻，只對「變動的 tile」細看。借鏡 KVM-over-IP / VNC 的增量更新與人眼中央窩成像。
2. **記得清（Action Script Narrator）** — 本地快速模型（Apple FoundationModels 3B / Qwen MLX）持續把操作寫成 human-readable 的劇本（L0 事件日誌 → L1 敘事步驟 → L2 段落摘要），滾動彙總。
3. **交棒快（Cloud Takeover）** — 熱鍵觸發時，把劇本（文字因果史）+ 焦點小圖交給 Claude（Computer Use），由大模型「續寫」未完成的 open loop，使用者免重新解釋。

混合架構：敏感資料與高頻觀察留本地，複雜推理與動作規劃上雲；兩者之間有明確隱私閘門（PII 遮罩 + app 黑名單 + 上海團隊 PIPL 跨境合規）。

## Repo 結構

```
CoPartner/
├── docs/                 設計與架構文件（單一事實來源）
│   ├── design/           V1 / V2 / V2.1 完整設計文件
│   ├── architecture/     架構總覽、程序拓樸、資料流
│   ├── adr/              架構決策紀錄 (Architecture Decision Records)
│   └── privacy/          資料分類與 PII 政策
├── apps/CoPartner/       macOS app（SwiftUI menu bar，XcodeGen project.yml）
├── packages/CoPartnerKit Swift Package（多 target 函式庫，app 與測試共用）
│   └── Sources/
│       ├── CoPartnerCore     共用型別（ActionStep、TileEvent、ContextEnvelope…）
│       ├── CaptureEngine      ScreenCaptureKit + Metal tile hashing + foveation
│       ├── ScriptNarrator     L0/L1/L2 劇本敘事器（FoundationModels）
│       ├── MemoryStore        sqlite-vec 三層記憶
│       ├── CloudRouter        LiteLLM / Claude Computer Use 客戶端
│       └── ActionExecutor     sandboxed 動作執行 + 風險分級
├── sidecar/              Python 本地推理 sidecar（MLX：Qwen2.5-VL / OCR）
├── infra/litellm/        LiteLLM Gateway 設定 + docker-compose
├── scripts/              bootstrap / 權限檢查 / 開發啟動
└── .github/workflows/    CI
```

## 開發狀態

🚧 **規劃 / 骨架階段**。目前 repo 包含完整設計文件與專案骨架，尚未有可執行實作。
見 [`docs/roadmap.md`](docs/roadmap.md) 的 milestone 規劃（M0 擷取引擎原型起步）。

## 快速開始（開發環境）

需求：macOS 26+、Xcode 16+、[XcodeGen](https://github.com/yonseyong/XcodeGen)、Python 3.12+、[Colima](https://github.com/abiosoft/colima) 或 OrbStack（跑 LiteLLM）。

```bash
# 1. 安裝開發依賴與產生 Xcode 專案
./scripts/bootstrap.sh

# 2. 檢查 / 引導 macOS TCC 權限（螢幕錄製、輔助使用、輸入監控）
./scripts/permissions-check.sh

# 3. 啟動本地推理 sidecar
cd sidecar && uv sync && uv run copartner-sidecar

# 4. 啟動 LiteLLM Gateway
cd infra/litellm && docker compose up -d
```

## 設計文件

| 文件 | 內容 |
|---|---|
| [`docs/design/v1_full-design.md`](docs/design/v1_full-design.md) | V1：完整系統設計（定頻擷取基線、平台 API、混合模型、路線圖） |
| [`docs/design/v2_smart-capture-engine.md`](docs/design/v2_smart-capture-engine.md) | V2：智慧擷取引擎（foveated / dirty-region / tile） |
| [`docs/design/v2.1_action-script-narrator.md`](docs/design/v2.1_action-script-narrator.md) | V2.1：操作劇本敘事與雲端交棒機制 |

## 隱私與合規

本機優先、敏感不出境。詳見 [`docs/privacy/data-classification.md`](docs/privacy/data-classification.md)。
涉及上海團隊個資時受中國 PIPL 跨境條款約束；台灣端受 PDPA 約束。

## 授權

待定（TODO：選擇授權條款）。
