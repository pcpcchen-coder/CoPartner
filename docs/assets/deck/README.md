# 簡報檔（.pptx）

**[`CoPartner-進度全景.pptx`](CoPartner-進度全景.pptx)** — 20 頁、16:9、**每頁都附講者備忘稿**。
內容依 [`docs/planning/ppt-material.md`](../../planning/ppt-material.md) 的大綱產出，數字全部來自真機實測。

| | |
|---|---|
| 頁數 | 20（1–3 開場／4–7 三大理念與四道閘／8–9 進度與規模／10–13 方法論與安全／14–17 真機教訓／18–20 現況與收尾）|
| 尺寸 | 13.33 × 7.5 in（16:9）|
| 字型 | 內文 Calibri、標題 Cambria、資料 Courier New——全是 Office 內建；中文走系統 fallback（macOS 為 PingFang TC）|
| 講稿 | 20 / 20 頁，在 PowerPoint 的「備忘稿」窗格或簡報者檢視畫面 |

## 場合裁切

| 場合 | 用哪幾頁 |
|---|---|
| 5 分鐘 lightning | 1・2・4・8・11・20 |
| 15 分鐘 tech share | 1–14 + 20 |
| 30 分鐘 deep dive | 全部 |
| 給非技術聽眾 | 1・2・3・4・8・12・18・19・20 |

## 重新產生

`gen.js` 是這份 pptx 的**產生器**——deck 不要手改，改 `gen.js` 後重跑，否則下次重生會蓋掉手改的部分。

```bash
npm install pptxgenjs
node gen.js "CoPartner-進度全景.pptx"
```

進度數字**硬寫在 `gen.js` 裡**（搜尋 `60 / 66`、`phases`、`ms` 三個陣列），與 `panorama.html` 一樣是衍生視圖——
事實來源仍是 [`docs/planning/implementation-backlog.md`](../../planning/implementation-backlog.md)。改進度時三處要一起更新。

### 視覺設計

沿用 `panorama.html` 那套：冷灰綠底 + 磷光琥珀重點色（琥珀＝「注意力」，呼應擷取引擎最亮的那塊 tile），
綠色只當語意色（完成）。母題是**小方磚**，從封面的 foveation 場、進度頁的 66 格 tile 陣列到清單前的小方點都在重複。
深色頁只有三張（封面／翻開執行開關／收尾），形成三明治結構。

關鍵視覺都是**原生畫的**，不是貼 `../diagrams/` 的 PNG——心智圖縮到投影片尺寸會看不清：

- 第 5 頁 foveation 場：8 × 6 tile 陣列，中央亮、周邊暗
- 第 8 頁進度地圖：66 個小方磚，一格一 step（綠＝完成、琥珀＝進行中、空格＝待驗收）
- 第 20 頁版本階梯：右欄長條是「跳出電腦的程度」

`../diagrams/` 的圖檔留給你自己排版時用。

### ⚠️ 在 Linux 上做視覺 QA 的注意事項

用 LibreOffice 轉 PDF 檢查時，「翻」「斷」這類複雜中文字會出現**字元重疊**。
已做對照測試：**Calibri / Cambria × 粗體 / 一般四種組合都一樣**，
所以那是容器內開源中文字型（WenQuanYi）的字寬計算問題，**不是 pptx 的缺陷**——
在 macOS／Windows 上以 PingFang TC 或微軟正黑體開啟即正常。
別為了這個去改字型，改了沒用。
