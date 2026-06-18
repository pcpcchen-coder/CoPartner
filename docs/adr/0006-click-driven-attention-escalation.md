# 6. 點擊驅動的注意力升級（click-driven attention escalation）

- 狀態：已接受
- 脈絡：foveation（ADR-0003）原本只用游標「位置」定義 attention region；但事件「種類」本身是強訊號——點擊代表一個意圖動作的起點，是資訊最密集的時刻；單純移動或靜置資訊量低。
- 決定：以事件加權的「注意力能量 A∈[0,1]」驅動擷取參數（region 大小 / 解析度 / FPS）：
  - **click** → `A=1.0` + 立即強制一次高解析擷取（涵蓋點擊後 ~300–500ms UI 反應窗）+ 擴大 region。
  - **drag** 維持高（0.85）；**keyDown** 錨定 focused element（0.8）；**scroll** 中等（0.6）；
    **move** 低且隨速度衰減（0.3·(1−speed)）；**idle** 衰減回 baseline（COLD）。
  - `A` 隨時間 decay（half-life ~2s），clicks 重新充能。
- 後果：把運算集中在「動作起點」這個最有價值的瞬間；與冷熱狀態機（WARM→HOT 立即升級，ADR-0003）
  與 Action Script Narrator（click = 天然 L0 事件邊界 / L1 step 起點，ADR-0004）整合。
  需處理連點 thrash（coalesce；週期性連點比照 DYNAMIC）與隱私（敏感 region 即使 A 高仍不擷取內容，ADR-0005）。
- 實作：packages/CoPartnerKit/Sources/CaptureEngine/CaptureEngine.swift 的 `AttentionModel`；
  設計細節見 docs/design/v2_smart-capture-engine.md §B.3.1。
