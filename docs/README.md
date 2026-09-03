# CoPartner 文件索引

> 全部設計、規劃、決策文件的入口。**先看 [`project-mindmap.md`](project-mindmap.md)**——一份文件看完專案全景與進度。

## 🧭 從這裡開始

| 你想知道 | 看這份 |
|---|---|
| 這專案在做什麼、做到哪了 | [`project-mindmap.md`](project-mindmap.md) — 心智圖 + 進度全景 |
| 下一步要做什麼、每步怎麼做 | [`planning/implementation-backlog.md`](planning/implementation-backlog.md) — **進度的單一事實來源** |
| 我要在 Mac 上驗收，怎麼跑 | [`planning/realmachine-runbook.md`](planning/realmachine-runbook.md) — 六個 🔒 里程碑逐步清單 |
| 換個 session 接手，要交接什麼 | [`planning/session-handoff.md`](planning/session-handoff.md) — 可獨立運作的交接包 |
| 要做簡報，素材在哪 | [`planning/ppt-material.md`](planning/ppt-material.md) — 投影片大綱、關鍵數字、講稿；圖檔在 [`assets/diagrams/`](assets/diagrams/) |
| 想直接投影 / 截圖一頁看完 | [`assets/panorama.html`](assets/panorama.html) — 單頁視覺版全景，用瀏覽器打開即可 |
| 系統怎麼運作的 | [`architecture/overview.md`](architecture/overview.md) → [`design/`](design/) |
| 安全邊界是什麼、怎麼驗 | [`design/sandbox-threat-model.md`](design/sandbox-threat-model.md) — 不變式 I1–I10；驗證指令見 repo 根 `README.md` |
| 為什麼這樣設計 | [`adr/`](adr/) — 七則架構決策紀錄 |

## 📁 目錄結構

### `planning/` — 規劃與進度

| 文件 | 內容 | 性質 |
|---|---|---|
| [`implementation-backlog.md`](planning/implementation-backlog.md) | V1 的 58 步 TDD backlog（step 53 已展開為 53.1–53.7），每步含目標／檔案／測試案例／DoD／as-built | **事實來源**，隨開發更新 |
| [`realmachine-runbook.md`](planning/realmachine-runbook.md) | 六個需要真 Mac 的里程碑（24／29／36／42／53／58）的三段式流程：我補膠水 → 你跑 → 你回報 | 隨驗收更新 |
| [`session-handoff.md`](planning/session-handoff.md) | 跨 session 交接包：專案是什麼、現在在哪、工作方式、踩過的坑、當前待辦、自我審查紀錄 | 里程碑翻牌時更新 |
| [`assistant-evolution-plan.md`](planning/assistant-evolution-plan.md) | V1 之後的版本階梯：V2 Listen（音訊＋訊息閘道）→ V3 Agent（技能引擎＋主動性）→ V4 Omni（穿戴） | 長期規劃 |
| [`dev-execution-plan.md`](planning/dev-execution-plan.md) | 模型分工（哪一步用哪個模型）、時程與訂閱費用評估 | 長期規劃 |
| [`ppt-material.md`](planning/ppt-material.md) | 簡報素材：投影片大綱、每頁要點、關鍵數字、講稿、Q&A 預備 | 衍生視圖 |
| [`phase-a-review.md`](planning/phase-a-review.md) | Phase A 完成後的階段回顧 | 歷史紀錄 |
| [`step18-dogfood.md`](planning/step18-dogfood.md) | M0 真機驗收（step 18）現場紀錄 | 歷史紀錄 |

### `design/` — 主設計文件

| 文件 | 內容 |
|---|---|
| [`v1_full-design.md`](design/v1_full-design.md) | V1 完整系統設計：定頻擷取基線、平台 API、混合模型、資料分類矩陣、路線圖 |
| [`v2_smart-capture-engine.md`](design/v2_smart-capture-engine.md) | V2 智慧擷取引擎：foveation、dirty-region、tile 冷熱狀態機、多解析度金字塔 |
| [`v2.1_action-script-narrator.md`](design/v2.1_action-script-narrator.md) | V2.1 操作劇本敘事：L0／L1／L2 三層、ContextEnvelope、takeover contract |
| [`sandbox-threat-model.md`](design/sandbox-threat-model.md) | 動作執行的安全設計：信任邊界 B0–B4、威脅 T1–T10、**可測不變式 I1–I10**、殘餘風險 R1–R6（R5／R6 已由真機實測解答） |

### `architecture/` — 架構速覽（皆為 Mermaid，GitHub 直接算圖）

- [`overview.md`](architecture/overview.md) — 三大支柱與模組相依
- [`data-flow.md`](architecture/data-flow.md) — 從像素到動作、接手時序
- [`process-topology.md`](architecture/process-topology.md) — 程序、沙箱、TCC 權限、信任邊界

### `adr/` — 架構決策紀錄

| # | 決策 |
|---|---|
| [0001](adr/0001-record-architecture-decisions.md) | 採用 ADR 記錄架構決策 |
| [0002](adr/0002-screencapturekit.md) | 用 ScreenCaptureKit 而非已 deprecated 的 CGDisplayStream |
| [0003](adr/0003-foveated-dirty-region-capture.md) | Foveated / dirty-region 擷取（V2 核心） |
| [0004](adr/0004-action-script-narrator.md) | Action Script Narrator：交棒要的是因果史，不是截圖（V2.1 核心） |
| [0005](adr/0005-hybrid-local-cloud-routing.md) | 混合本地／雲端路由與隱私邊界（PDPA／PIPL） |
| [0006](adr/0006-click-driven-attention-escalation.md) | 點擊驅動的注意力升級：事件種類本身是強訊號 |
| [0007](adr/0007-local-first-tiered-inference.md) | 本地優先的分層推理階梯與雲端升級時機 |

### `privacy/`

- [`data-classification.md`](privacy/data-classification.md) — 資料分類矩陣：絕不出本機／遮罩後可上雲／可上雲

### `assets/` — 簡報素材

| 檔案 | 內容 |
|---|---|
| [`assets/panorama.html`](assets/panorama.html) | **單頁視覺版全景**——里程碑燈號、Phase A–G 進度地圖、四道閘、方法論、真機教訓、版本階梯、誠實風險清單、數字附錄。單一檔案、無需建置，瀏覽器直接開；淺色／深色自動跟隨系統。適合直接投影或截圖進投影片 |
| [`assets/diagrams/`](assets/diagrams/) | 十張從心智圖匯出的圖，SVG（PowerPoint／Figma）+ 2x PNG（Keynote／Google Slides）兩版。清單與重新產生方式見 [`assets/diagrams/README.md`](assets/diagrams/README.md) |

`panorama.html` 也發佈了一份線上版（Claude Artifact），內容相同；repo 這份多了完整的 HTML 文件骨架，所以能離線直接開。

### 根目錄

- [`roadmap.md`](roadmap.md) — M0–M6 里程碑總覽與量化驗收標準
- [`project-mindmap.md`](project-mindmap.md) — 📊 心智圖與進度全景

## ✍️ 文件維護規則

1. **進度只有一個事實來源**：`planning/implementation-backlog.md`。改進度時**進度總覽表與該 step 詳細章節兩處都要改**——過去多次只改一處造成漂移（例：step 42 已真機通過但表格停在 ⬜）。
2. **真機結果進 runbook**，脈絡與過程紀錄進 `session-handoff.md`。
3. **衍生視圖最後同步**：`project-mindmap.md`、`assets/panorama.html`（裡面的數字是硬寫的，改進度時要一起改）、根目錄 `README.md`／`README.en.md`、`CHANGELOG.md`、`planning/ppt-material.md`。
4. **圖改了要重新匯出** `assets/diagrams/`（方法見該目錄 README）。
5. **架構決策先寫 ADR**：影響架構的變更，PR 應附對應 ADR（見 ADR-0001）。
