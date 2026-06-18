# macOS Ambient AI Assistant — 技術設計文件 V2（智慧螢幕擷取引擎）

> 本文件為 V1 的重大架構升級。V1 瓶頸是「定頻全畫面擷取 + 全畫面 OCR/VLM」，在 24GB Mac Mini M4 上長時間執行時資源全面承壓。V2 核心創新是 Smart Capture Engine：把擷取從 frame-centric 改為 region-centric，借用 KVM-over-IP / VNC 的 dirty-region 增量更新 + 人眼 foveated 兩套機制，只對「使用者正在注意的區域」與「實際變化的 tile」投入運算。
>
> 目標硬體：Mac Mini M4（10-core CPU / 10-core GPU，24GB），macOS 26 Tahoe（必要時降級相容 Sequoia 15）。

## TL;DR

- ScreenCaptureKit 原生就給 dirty rects（`SCStreamFrameInfo.dirtyRects`，macOS 12.3+，WWDC22 session 10155 示範「只編碼/傳輸變動區域」）。但此 API 有 idle frame、空陣列、contentRect 座標 bug、版本差異等可靠性陷阱，故 V2 採「SCK dirty rects 為主訊號 + Metal GPU per-tile dHash 為驗證/補強」，CPU 只做排程決策。
- foveation 由滑鼠（CGEventTap mouseMoved）+ 焦點（AXUIElement focused element frame）雙軸驅動：焦點區 600×400pt 做 4–8 FPS 原生 2x 高解析，周邊做 0.5–1 FPS 縮圖；tile 冷熱狀態機（COLD→WARM→HOT→DYNAMIC）把影片/動畫區自動降頻並標記為「不需 OCR」。
- 量化預期（推導估算）：相對 V1，V2 可省 ~80–95% OCR 像素吞吐、~85% 磁碟寫入、以及大量雲端 token。M0 milestone 的唯一目的就是在真機把這些數字量出來。

## Key Findings

1. dirty rects 是 first-party、免費、可靠性需防禦。SCK 透過 `CMSampleBufferGetSampleAttachmentsArray` 提供 `.dirtyRects`/`.contentRect`/`.contentScale`/`.scaleFactor`；`.status == .idle` 代表沒變（天然 dedup）。但 status 常回 idle、dirtyRects 可能為空、Sequoia 15.6.1 有 contentRect X=48 bug，故必須用 Metal hash 驗證。CGDisplayStream macOS 14+ deprecated。
2. 沒有現成的 macOS foveated/tile-based dirty-region 擷取開源專案。screenpipe 最接近，但它是 event-driven + adaptive FPS + 整幀 dedup，非真正 tile/foveated。V2 的 foveated capture 在 macOS 生態是新東西。
3. KVM/VNC 機制可借鏡但要分清：PiKVM uStreamer 只做整幀 byte-wise dedup（`--drop-same-frames`），非 per-tile；真正 tile diff 在 VNC——TigerVNC 優先用 XDAMAGE 事件式通知，fallback 用 PollingManager 32×32 tile 掃描（MaxProcessorUsage 預設上限 35% CPU）。V2 借用 tile-polling + damage-hint，但把「不同方式編碼影片區」換成「不同方式理解（跳過 OCR）」。
4. 本地模型棧：Qwen2.5-VL-7B via MLX/mlx-vlm（4-bit ~5–6GB）做視覺語意；Apple FoundationModels（macOS 26，~3B，`LanguageModelSession` + `@Generable`/`@Guide`）做意圖分類/路由；Vision `VNRecognizeTextRequest`（`regionOfInterest`）只跑 dirty tiles。
5. Claude Computer Use（2026-05）：beta header `computer-use-2025-11-24`、tool `computer_20251124`，支援 Opus 4.7/4.6、Sonnet 4.6、Opus 4.5；4.6 家族 ~1568px/1.15MP 上限，Opus 4.7 提高到 ~3.75MP；Retina ratio=2 須 downscale 或座標 ÷2；Anthropic 指出「切 tile 分送不提升點擊精度」→ 對 Claude 仍送焦點整圖。
6. PIPL（上海團隊）：跨境需 CAC 安全評估 / SCC 備案 / 認證三擇一（2026/1/1 認證正式化）；<10萬人個資（不含敏感）/履約必需可豁免；以同意為基礎需單獨同意。

## A. V2 系統架構總覽

```
[Smart Capture Engine] SCStream(SCK +dirtyRects +IOSurface)
  → Dirty-Region Resolver (SCK rects + Metal tile hashing)
  → Tile State Machine (cold/warm/hot/dynamic) + Foveation Scheduler
  Attention Drivers: CGEventTap mouseMoved / AXObserver focused elem
  Reference Frame + Delta Store (I/P frame) | Local OCR (Vision ROI)
     │ 語意事件 + 拼接圖 via XPC/Unix socket
[Observation & Memory] L1 RAM → L2 SQLite+sqlite-vec → L3 加密摘要 + 注意力熱圖
     │                                  │
[Local Inference]                  [Cloud Router (LiteLLM)]
 Qwen2.5-VL-7B MLX / FM 3B / OCR   → Claude (computer-use-2025-11-24)
                                   ContextEnvelope: 焦點高解析+周邊縮圖+dirty摘要+熱圖
     │                                  │
[Menu Bar UI] + [Action Executor (sandboxed XPC)]
```

程序拓樸與 V1 同，但擷取層改為 Smart Capture Engine。TCC 陷阱：所有需 Screen Recording 的元件必須打包成簽章 .app bundle（macOS 26.1）。

V1→V2 差異：擷取單位（整 frame → tile + attention region 多頻率）、變化偵測（無 → SCK dirtyRects + Metal dHash）、解析度（全畫面同解析 → 焦點 2x/周邊縮圖）、OCR（每張全畫面 → 只 dirty tiles）、影片區（照常 → DYNAMIC 降頻跳 OCR）、持久化（整張 JPEG → reference + deltas）、雲端打包（整張高解析 → 焦點+縮圖+摘要+熱圖）。

## B. 智慧擷取引擎深度設計（核心）

設計原則：OS 給的訊號優先（SCK dirty rects），GPU 補強（Metal tile hash），CPU 只做排程決策。

### B.1 SCK dirty rects
每個 frame 的 CMSampleBuffer attachments 提供 `SCStreamFrameInfo.dirtyRects`。WWDC22 10155：用 dirty rects 只編碼/傳輸變動區域，接收端把更新貼到前一張——正是 V2 reference+delta 模型。可靠性陷阱：status 常回 idle（天然 dedup 但不能假設每 callback 都有新 IOSurface）、dirtyRects 可能空/保守、Sequoia 15.6.1 contentRect X=48 bug。決策：SCK 主訊號，Metal per-tile hash 驗證。

### B.2 Metal per-tile dHash
每 threadgroup 處理一個 tile，輸出 uint64；CPU 比 `popcount(h_now ^ h_prev)`：0=沒變、小=微變（過濾游標殘影）、大=真變。1440p 切 128px ≈180 tile，M4 GPU dispatch sub-millisecond，比 CPU 逐 tile diff 便宜一個數量級。hash 同時當持久化 dedup key + 驅動冷熱狀態機 + dynamic 偵測。（shader 置於 CaptureEngine/Resources/TileHash.metal）

### B.3 滑鼠驅動 attention region
CGEventTap 監聽 mouseMoved/leftMouseDown/scrollWheel（global、低延遲、`.listenOnly`）。attention region = 游標中心 600×400pt，內部 tile 升 hot-priority（2x、4–8 FPS）。滑鼠靜止衰減、快速滑動降頻（模擬 saccade vs fixation）。

#### B.3.1 事件加權的注意力能量模型（ADR-0006）
不只用游標「位置」，更用事件「種類」決定注意力強度——因為**點擊是一個意圖動作的起點**，點擊後 ~300–500ms（UI 反應、彈窗、選取、焦點變更）是整段操作中資訊最密集的時刻；單純移動是滑鼠在路上（ballistic/saccade），靜置則資訊量最低。

以一個注意力能量 `A ∈ [0,1]` 驅動擷取參數（region 半徑 / 解析度 scale / FPS），各事件取 max 後隨時間衰減（half-life ~2s，clicks 重新充能）：

| 事件 | 對 A 的作用 | 理由 |
|---|---|---|
| **click（mouseDown）** | `A = 1.0` + **立即強制一次高解析擷取** + 擴大 region | 動作起點，最該細看 |
| drag（mouseDragged） | `A = max(A, 0.85)` 並追蹤移動中的 region | 選取/拖曳進行中 |
| keyDown（打字） | `A_focus = max(., 0.8)`，**錨定 focused element（§B.4）非游標** | 打字常不在滑鼠處 |
| scrollWheel | `A = max(A, 0.6)` | 內容在游標下變動，偏閱讀 |
| mouseMoved | `A = max(A, 0.3·(1−speed))`，**快速移動更低** | 過渡中，不升級 |
| idle（N 秒無事件） | 只衰減 → 回 baseline（COLD） | 周邊心跳 0.2 FPS |

`A` 分帶映射到擷取參數（見 `CaptureEngine/AttentionModel`）：`≥0.7` HOT(400pt/2x/8fps)、`0.4–0.7` 升高(300pt/1x/4fps)、`0.15–0.4` WARM(250pt/1x/2fps)、其餘 COLD(0.5x/0.2fps)。

**整合**：click 可把 attention region 內 tile 立即從 WARM→HOT（§B.6）；click 也是 Action Script Narrator（v2.1）天然的 L0 事件邊界 / L1 step 起點。**邊界處理**：連點/雙擊 coalesce 避免 thrash，週期性高頻連點（如遊戲）比照 DYNAMIC；敏感 region 即使 A 高仍不擷取內容（§G）。click 常先於 AX 的 focus/window 變更通知 → 與 `AXObserver` 併用觸發強制照一張。

### B.4 焦點元件定義重點區域
`AXUIElementCreateSystemWide()` + `kAXFocusedUIElementAttribute` 取 focused element 的 AXFrame；`AXObserver` 訂閱 focused element/window 變更。滑鼠軸 + 焦點軸取聯集為高優先區；兩者皆閒置 → 退回低頻概覽。能拿 AX 文字的 tile 不必跑 OCR（accessibility-first，OCR fallback，對齊 screenpipe）。

### B.5 多解析度金字塔
L0 焦點層（attention region 內，原生 2x，full color，送 VLM/雲端）；L1 周邊變動層（dirty 但 attention 外，1x/0.5x）；L2 概覽層（整張縮圖 ≤1024px，0.5–1 FPS）。用 MTLBlitCommandEncoder.generateMipmaps 零額外擷取成本產生多層。

### B.6 冷熱狀態機 + 影片降頻（CPU 不爆關鍵）

| 狀態 | 判定 | 頻率 | 解析度 | OCR | 持久化 |
|---|---|---|---|---|---|
| COLD | N秒無變 | 0.2 FPS 心跳 | 縮圖 | 否 | reference 既有 |
| WARM | 最近變動 | 1–2 FPS | 1x | 是(dirty時) | 存 delta |
| HOT | 持續變動 | 4–8 FPS | 焦點2x | 是(節流) | 存 delta(去重) |
| DYNAMIC | 高頻+規律+大面積 | 1–2 FPS 縮圖 | 0.5x | 否 | 只存語意標籤 |

DYNAMIC 偵測：連續多幀大 Hamming distance + 大面積 + 間隔規律（30/60fps 倍數）→ 判為影片，從 OCR/delta pipeline 剔除，只記「播放動態內容」。借鏡 TigerVNC（32×32 tile + MaxProcessorUsage 35% 上限）。

### B.7 Reference frame + delta（I/P frame）
維護壓縮 reference（I-frame）；之後只記 dirty tiles 內容+座標+hash（P-frame）。需完整畫面時 reference ⊕ deltas 重建。每 T 秒或累積 delta > 畫面 X% 時 re-baseline。同時是持久化（C）與 prompt caching（E）基礎。

### B.8 局部 OCR
Vision `VNRecognizeTextRequest`（`.accurate`、`recognitionLanguages=["zh-Hant","en-US"]`、`regionOfInterest` 限 dirty tile）。macOS 14+ 可用更強 LiveText 後端。V2 只對少數 dirty tile 跑，延遲遠低於整張。

### B.9 量化估算
OCR 像素吞吐 ~80–95%↓；磁碟 ~85%↓（對齊 screenpipe 300MB/8hr vs 2GB）；CPU 顯著↓；雲端 token 大幅↓；電力↓（多數時間 COLD）。皆為推導估算，M0 須真機驗證。

## C. 觀察緩衝與記憶（V2）

tile event → connected-component 合併 region → AX hit-test 歸屬 window → 時間滑窗黏合成 span → app-level 語意事件（只有 window/app 級進記憶）。持久化只存變動 tile，dHash 當去重 key，DYNAMIC 不存像素只存標籤。三層記憶：L1 RAM ring buffer / L2 SQLite+sqlite-vec（vec0 float[768] KNN）/ L3 加密日摘要。注意力熱圖：tile grid 衰減式 heatmap，只存聚合衰減權重、不存原始座標時序、TTL。

## D. 本地模型餵圖策略（V2）

Qwen2.5-VL-7B MLX（4-bit ~5–6GB，vision feature caching 多輪快 ~3×）只餵焦點 L0 + dirty tiles 拼接圖（content-packing），image token 砍一個數量級。Apple FoundationModels 3B 做意圖分類/路由（`@Generable`，需 availability 檢查 + fallback）。三段分工：FM 3B（意圖/路由，輕快免費）→ Vision OCR（dirty tile 文字，ANE）→ Qwen2.5-VL（圖文語意，最貴，只對焦點拼接圖）。

## E. 雲端 Claude 整合（V2）

ContextEnvelope：focus_image（焦點 L0 2x 小圖）+ overview_thumb（≤1024px）+ dirty_summary（文字）+ attention_heatmap（稀疏權重）+ focused_text（AX ±200 字）。熱圖轉自然語言幫 Claude 聚焦。Computer Use：beta `computer-use-2025-11-24`、`computer_20251124`；Opus 4.7 ~3.75MP；Retina 座標 ÷2；切 tile 分送不提升精度 → 送焦點整圖。LiteLLM + prompt caching：reference/縮圖/系統 prompt 放穩定前綴命中 cache。PIPL guard：含上海個資/敏感畫面 → 強制 local-only。

## F. 觸發與介入流程（V2）

焦點區一直 4–8 FPS 原生解析度被擷取且有最新 OCR/AX（warm cache），熱鍵觸發只需打包，省掉現照與現 OCR。時序：熱鍵 → XPC 取 RAM 熱 envelope（~5–20ms）→ sqlite-vec 撈歷史 → FM 3B 意圖+路由 → 本地/雲端 → tool_use → 高風險 confirm → sandboxed executor。

## G. 隱私與安全（V2）

tile 級遮罩：AX kAXSecureTextField + URL/標題啟發式 + OCR 正則（卡號/身分證/API key）→ 敏感 tile 永不進 reference/持久化/出網，只記「此處有敏感輸入」。熱圖只存聚合衰減權重。黑名單用 SCContentFilter 源頭排除整 app（建議用 includingApplications 白名單實作，避開空陣列 bug；排除自身 app 避免錄製迴圈）。PIPL：雲端路徑處理到上海成員個資畫面預設不出境，確需出境走 SCC 備案 + 單獨同意。

## H. 安全沙箱與動作執行（沿用 V1，精簡）

動作執行隔離於 sandboxed XPC；風險分級（Low 自動 / Medium 一鍵確認 / High 強制 explicit confirm）；Claude tool_use 先經本地 policy guard；MCP 工具用 deterministic 三層 gating（非 prompt 防護）；高風險支援 dry-run/可中止；加密稽核日誌。

## I. 實作技術棧（V2）

新增 Metal compute shader（tile dHash）、Swift（擷取引擎/AX/CGEventTap）、可選 Rust（高頻 tile 處理，非必要）。參考開源：ScreenCaptureKit（dirty rects 唯一權威）、screenpipe（event-driven 架構參考）、uStreamer（整幀 dedup）、TigerVNC（XDAMAGE + 32×32 tile，真正 tile-diff 參考）、RFB/RFC 6143、sqlite-vec、mlx-vlm。無現成 macOS foveated/tile dirty-region 擷取開源實作——V2 屬新工程。

## J. 路線圖（V2，5–10 hrs/週）

| Milestone | 交付 | 週期 | 驗收 |
|---|---|---|---|
| M0 擷取引擎原型 | SCK + dirtyRects + Metal tile dHash + 滑鼠 attention，純擷取無 AI | 3–4 週 | 真機 CPU%/漏抓率/延遲；V1 vs V2 對照 |
| M1 冷熱狀態機 + DYNAMIC | 狀態機 + 影片降頻跳 OCR + foveation | 2–3 週 | 播 1080p CPU 不超 baseline；正確標 DYNAMIC |
| M2 局部 OCR + AX 文字 | regionOfInterest OCR + AX 優先 | 2 週 | OCR 吞吐 ≤ V1 20% |
| M3 記憶系統 | reference+delta + sqlite-vec + 熱圖 | 2–3 週 | 8hr ≤ ~400MB |
| M4 本地推理 | Qwen2.5-VL MLX + FM 意圖 | 2–3 週 | 本地路徑 sub-second |
| M5 雲端 + 動作 | LiteLLM + Claude CU + envelope + executor | 3–4 週 | 熱鍵往返延遲；高風險強制確認 |
| M6 隱私 + 黑名單 | tile 遮罩 + SCContentFilter + 熱圖隱私 | 2 週 | 密碼欄 100% 遮；黑名單 0 frame |

## K. 成本與效能估算（V2）

假設 1440p、128px tile ≈180 tile、辦公 workload 變動 <10–20%。CPU：idle 略過 + GPU dHash sub-ms + 只 dirty tile OCR。RAM：多一份壓縮 reference + hash 陣列（微量）；Qwen 4-bit ~5–6GB 最大占用。磁碟：~300MB/8hr 級距（~85%↓）。電力：多數 COLD 顯著省。雲端 token：焦點小圖 + 摘要 + reference 走 cache。皆推導估算，M0 換成真機值。

## L. 風險、限制、倫理（V2 新增）

dirty-region 漏抓（快速彈出 dialog）→ attention region 永遠高頻 + AXObserver 強制照 + COLD 心跳兜底；hot/DYNAMIC 資源風險 → 保守判定 + 全域 OCR 預算上限（類比 VNC 35%）；DYNAMIC 誤判（即時 log/股價）→ AX 可得文字的 tile 不套 DYNAMIC + per-app override；滑鼠 attention 盲點（純鍵盤）→ 焦點軸第二來源 + 鍵盤活動升級對應視窗；SCK dirtyRects 跨版本可靠性 → Metal hash 永遠當 ground truth。

## M. V1 → V2 遷移與決策

可沿用：TCC 流程（補 .app bundle）、menu bar UI、Action Executor、LiteLLM 路由、記憶骨架、MCP 工具層。

降級路徑：
- Tier 1（完整）：SCK dirtyRects + Metal per-tile dHash + 冷熱狀態機 + foveation 雙軸 + DYNAMIC。
- Tier 2（簡化，建議 MVP 起點）：只做滑鼠/焦點 attention region 高頻高解析 + 周邊定頻縮圖，不做完整 tile 狀態機與 Metal hash，直接信任 SCK idle status 做整幀 dedup。
- Tier 3（保底）：純 SCK + idle 略過 + 全畫面 OCR 節流。

建議：M0 先做 Tier 2 驗證收益與真機數字；若影片區仍造成 CPU 尖峰，再投入 Tier 1 的 DYNAMIC 狀態機。

## Caveats

所有 V1 vs V2 量化改善皆為推導估算，唯一公開實證為 screenpipe 的 vendor 自報數字，無獨立 benchmark 比較 dirty-region vs 全幀擷取於螢幕場景。SCK dirtyRects 在 macOS 12.3–26 各版本可靠性不一，是 V2 最大技術不確定性。macOS 26 無新公開 SCK dirty-region 強化 API。FoundationModels 受限（~3B、小 context、需 availability 檢查 + fallback）。無現成 macOS foveated/tile dirty-region 擷取開源專案可直接抄——強烈建議 Tier 2 漸進落地。PIPL 規則仍在演進，跨境合規請以最新法規與專業法律意見為準。
