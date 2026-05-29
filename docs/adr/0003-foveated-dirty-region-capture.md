# 3. Foveated / dirty-region 擷取（V2 核心）

- 狀態：已接受
- 脈絡：定頻全畫面擷取 + 全畫面 OCR 在 24GB M4 上長時間執行成本過高，影片區尤其燙手。
- 決定：滑鼠/焦點區高解析高頻、周邊低解析低頻；切 tile、只對 dirty tile 細看；
  SCK dirtyRects 為主訊號、Metal per-tile dHash 驗證；tile 冷熱狀態機自動把影片標為 DYNAMIC 並跳過 OCR。
- 後果：預期大幅降低 CPU/OCR/磁碟/雲端 token（待 M0 真機量化）；增加擷取引擎複雜度，提供 Tier 2 降級路徑。
