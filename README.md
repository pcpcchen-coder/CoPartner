# CoPartner

*繁體中文 · [English](README.en.md)*

> 一個在 macOS 上持續觀察你的操作、用本地模型把行為寫成「操作劇本」、並在你按下熱鍵時由雲端大模型接手完成任務的 **Ambient AI Assistant**。 (補上全日語音錄音後的文字轉換摘要，並且可以透過語音互動交棒!)

**首要目標平台**：Mac Mini M4 / Apple Silicon，macOS 26 Tahoe（向下相容 Sequoia 15 為次要目標）。

## 這是什麼

CoPartner 由三個核心理念組成：

1. **看得省（Smart Capture Engine）** — 不做定頻全畫面截圖，改用 foveated + dirty-region 擷取：滑鼠/焦點區高解析高頻，周邊低解析低頻，只對「變動的 tile」細看。借鏡 KVM-over-IP / VNC 的增量更新與人眼中央窩成像。
2. **記得清（Action Script Narrator）** — 本地快速模型（Apple FoundationModels 3B / Qwen MLX）持續把操作寫成 human-readable 的劇本（L0 事件日誌 → L1 敘事步驟 → L2 段落摘要），滾動彙總。
3. **交棒快（Cloud Takeover）** — 熱鍵觸發時，把劇本（文字因果史）+ 焦點小圖交給 Claude（Computer Use），由大模型「續寫」未完成的 open loop，使用者免重新解釋。(可語音交棒)

混合架構：敏感資料與高頻觀察留本地，複雜推理與動作規劃上雲；兩者之間有明確隱私閘門（PII 遮罩 + app 黑名單 + 上海團隊 PIPL 跨境合規）。

## Repo 結構

```
CoPartner/
├── docs/                 設計與架構文件（單一事實來源，索引見 docs/README.md）
│   ├── project-mindmap.md  📊 心智圖與進度全景（視覺入口）
│   ├── planning/         實作 backlog、真機 runbook、交接包、版本演化、簡報素材
│   ├── design/           V1 / V2 / V2.1 完整設計 + 沙箱威脅模型
│   ├── architecture/     架構總覽、程序拓樸、資料流（Mermaid）
│   ├── adr/              架構決策紀錄 (Architecture Decision Records)
│   ├── assets/           簡報素材：deck/（.pptx）、panorama.html、diagrams/
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

**可運作的軟體，開發中。** 不再是骨架——app 跑得起來，在真機上持續觀察並敘事。
標 ✅ 的是**真機 dogfood 驗過**的，不只是 CI 綠。

| 里程碑 | 狀態 |
|---|---|
| 操作時間機器（事件日誌 → 可讀劇本）| ✅ 真機通過 |
| 焦點區局部 OCR | ✅ 真機通過，吞吐 18%（目標 ≤20%）|
| FoundationModels 本地 L1 敘事 | ✅ 真機通過，1373–2388ms／step；關掉 Apple Intelligence 自動降級規則式 |
| 雲端接手——契約、串流、確認 HUD | ✅ 真機通過 |
| 雲端接手——沙箱執行 | 🚧 進行中（見 backlog step 53.1–53.6）|
| 影片動態 tile、向量記憶、最終隱私稽核 | 🔒 待做 |

進度的單一事實來源是 [`docs/planning/implementation-backlog.md`](docs/planning/implementation-backlog.md)；
真機驗收清單見 [`docs/planning/realmachine-runbook.md`](docs/planning/realmachine-runbook.md)。

📊 **一頁看完全貌**：[`docs/project-mindmap.md`](docs/project-mindmap.md)——心智圖、進度地圖、
資料流、安全邊界、版本階梯。簡報素材有三種形式：
[`docs/assets/deck/`](docs/assets/deck/)（20 頁 .pptx，附講稿）、
[`docs/assets/panorama.html`](docs/assets/panorama.html)（單頁視覺版）、
[`docs/assets/diagrams/`](docs/assets/diagrams/)（圖檔 SVG／PNG）。

### 自己驗安全邊界

安全性質不是用宣稱的，是用示範的。兩個腳本不需要 Xcode 就能跑：

```bash
./scripts/sandbox-verify.sh                                   # 沙箱成對驗證
swiftc -O -o /tmp/xpc-probe scripts/xpc-probe.swift && /tmp/xpc-probe   # 拒絕路徑
```

`sandbox-verify.sh` 值得一讀，即使你不跑它——裡面記著一個花了好幾輪才學會的教訓：
**只測「擋得住」會製造假的信心。** `deny default` 之下幾乎什麼都起不來，
所以一個「什麼都擋」的 profile 會通過每一條負向測試。

## 快速開始（開發環境）

需求：macOS 26+、Xcode 16+、[XcodeGen](https://github.com/yonseyong/XcodeGen)、Python 3.12+、[Colima](https://github.com/abiosoft/colima) 或 OrbStack（跑 LiteLLM）。

```bash
# 1. 安裝開發依賴與產生 Xcode 專案
./scripts/bootstrap.sh
open apps/CoPartner/CoPartner.xcodeproj      # 然後 ⌘R

# 2. 檢查 / 引導 macOS TCC 權限（螢幕錄製、輔助使用、輸入監控）
./scripts/permissions-check.sh
```

CoPartner 是 `LSUIElement` app——沒有 Dock 圖示、沒有視窗，從選單列的眼睛圖示操作。

⚠️ **增刪檔案後一定要重跑 `./scripts/bootstrap.sh`**：Xcode 專案由 `project.yml` 產生、不入庫。

**日常使用不需要 sidecar 與 LiteLLM**：OCR 走 macOS Vision、敘事在本機跑。
sidecar 只留給選用的視覺語言模型路徑：

```bash
cd sidecar && uv sync && uv run copartner-sidecar     # 選用
cd infra/litellm && docker compose up -d              # 選用（雲端接手才需要）
```

## 設計文件

| 文件 | 內容 |
|---|---|
| [`docs/design/v1_full-design.md`](docs/design/v1_full-design.md) | V1：完整系統設計（定頻擷取基線、平台 API、混合模型、路線圖） |
| [`docs/design/v2_smart-capture-engine.md`](docs/design/v2_smart-capture-engine.md) | V2：智慧擷取引擎（foveated / dirty-region / tile） |
| [`docs/design/v2.1_action-script-narrator.md`](docs/design/v2.1_action-script-narrator.md) | V2.1：操作劇本敘事與雲端交棒機制 |
| [`docs/design/sandbox-threat-model.md`](docs/design/sandbox-threat-model.md) | 沙箱威脅模型：信任邊界 B0–B4、威脅 T1–T10、可測不變式 I1–I10 |
| [`docs/project-mindmap.md`](docs/project-mindmap.md) | 📊 心智圖與進度全景（視覺入口）|
| [`docs/README.md`](docs/README.md) | 全部文件索引與維護規則 |

## 隱私與合規

本機優先、敏感不出境。詳見 [`docs/privacy/data-classification.md`](docs/privacy/data-classification.md)。
涉及上海團隊個資時受中國 PIPL 跨境條款約束；台灣端受 PDPA 約束。

## 授權

待定（TODO：選擇授權條款）。
