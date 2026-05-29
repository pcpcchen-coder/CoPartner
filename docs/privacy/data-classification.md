# 資料分類與 PII 政策

| 類別 | 範例 | 處置 |
|---|---|---|
| 絕對不出本機 | 密碼欄、銀行 app、Keychain、私訊對話、ssh key | app 黑名單（SCContentFilter）+ AX role filter，連 frame 都不擷取 |
| 遮罩後可上雲 | 一般 email、人名、客戶名、IP、手機 | Presidio + FoundationModels redact，以 placeholder 上雲 |
| 可直接上雲 | 開源 code、公開文件、自寫 Markdown | 直接送 |
| 業務敏感（EV/EMS） | 換電站 API、客戶 SOC、內部 schema | local-only 或 Anthropic ZDR 端點 |

## 跨境合規
- **台灣 PDPA**：新設個人資料保護委員會（PDPC）；境外傳輸限制條款。
- **中國 PIPL §38**（上海團隊）：跨境需 CAC 安全評估 / SCC 備案 / 認證三擇一，且需單獨同意。
- 預設：只觀察使用者自己螢幕；含上海成員個資畫面不出境。

## 自訂 PII recognizer（給 Presidio）
- TW 身分證：`[A-Z][12]\d{8}`
- TW 手機：`09\d{8}`
- CN 身分證：`\b\d{17}[\dXx]\b`

## 透明性
操作劇本為 human-readable，交棒前的內容可逐行審查；所有 AI 動作寫入加密稽核日誌。
