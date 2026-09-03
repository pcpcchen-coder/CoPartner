# 圖表素材（PPT／簡報用）

由 [`docs/project-mindmap.md`](../../project-mindmap.md) 的 Mermaid 區塊匯出。**每張都有 SVG 與 PNG 兩版**：

- **SVG** — 向量、放大不糊。PowerPoint 2016+／365、Figma、Illustrator 可直接匯入並保持可縮放。
- **PNG** — 2x 解析度、白底。Keynote、Google Slides、貼進聊天室都適用。

| 檔名 | 內容 | 長寬比 | 建議用在 |
|---|---|---|---|
| `01-overview-三大理念` | 產品全景：看得省／記得清／交棒快 + 橫切關注 | 3.2 : 1 | 開場、全場地圖 |
| `02-architecture-模組地圖` | 七個 Swift target × 檔案 × 完成狀態 | 2.5 : 1 | 技術聽眾的架構頁 |
| `03-progress-進度地圖` | Phase A–G 的進度，含真機實測數字 | 2.4 : 1 | **進度頁（最常用）** |
| `04a-dataflow-本地感知鏈` | 螢幕／鍵鼠／AX → L0 → L1 → L2 → 記憶 | 4.9 : 1 | 核心機制（前半）|
| `04b-dataflow-出境與雲端` | 熱鍵 → 打包 → 出境閘門 → gateway → 提議 | 7.4 : 1 | 橫幅式流程帶 |
| `04c-dataflow-風險閘與執行` | 風險分級 → HUD 確認 → XPC → sbpl → 稽核 → undo | 6.3 : 1 | **四道閘（最有料）** |
| `05-security-安全隱私邊界` | 縱深五層隱私 + I1–I10 + 翻開後的能力範圍 | 2.4 : 1 | 安全／隱私頁 |
| `06-versions-版本階梯` | V1 → V2 Listen → V3 Agent → V4 Omni | 2.2 : 1 | 願景／收尾 |
| `07-critical-path-M5關鍵路徑` | M5 剩下什麼與驗收清單 | 1.1 : 1 | 「現在卡在哪」 |
| `08-docs-文件地圖` | docs/ 全部文件的組織 | 2.1 : 1 | 附錄／Q&A 備用 |

> 04b／04c 是**長條橫幅**（6–7 : 1），適合橫跨投影片中段當流程帶；不適合塞進半版。
> 要直式版本的話，把 `.mmd` 的 `flowchart LR` 改成 `flowchart TD` 重新匯出即可。

## 重新產生

圖表的**事實來源是 `docs/project-mindmap.md` 的 Mermaid 區塊**，不是這些檔案。心智圖改了之後重新匯出：

**線上（最省事）**：複製 ` ```mermaid ` 區塊內容 → 貼到 [mermaid.live](https://mermaid.live) → Actions → SVG／PNG。深色簡報記得先切 `dark` theme。

**本機（批次）**：

```bash
npm install @mermaid-js/mermaid-cli
# 把每個 mermaid 區塊存成 .mmd 後：
mmdc -i 圖.mmd -o 圖.svg               # 向量
mmdc -i 圖.mmd -o 圖.png -s 2 -b white # 2x PNG
```

搭配講稿與投影片大綱見 [`docs/planning/ppt-material.md`](../../planning/ppt-material.md)；
把這些內容排成一頁的視覺版見 [`docs/assets/panorama.html`](../panorama.html)；
做好的 20 頁簡報檔見 [`docs/assets/deck/`](../deck/)（它的關鍵視覺是原生畫的，沒有貼這裡的 PNG）。
