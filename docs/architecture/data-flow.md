# 資料流

1. SCStream 產生 frame + dirtyRects；Metal per-tile dHash 驗證 → TileEvent。
2. TileEvent + CGEventTap（鍵鼠）+ AX（焦點元件/文字）+ 剪貼簿 → 結構化事件。
3. ScriptNarrator：事件 → L0 日誌（模板）→ L1 ActionStep（FoundationModels）→ L2 摘要。
4. MemoryStore：L1/L2 寫入 sqlite-vec（劇本=檢索主幹）。
5. 熱鍵：打包 ContextEnvelope（劇本為主 + 焦點小圖）→ PII 閘門 → CloudRouter → Claude。
6. Claude tool_use → 風險分級 → （高風險 confirm）→ ActionExecutor。
7. 全程寫加密稽核日誌。

敏感資料（密碼欄/銀行/上海團隊個資）在步驟 5 的閘門被擋下，改走 local-only。
