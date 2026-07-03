# CoPartner 版本演化總規劃：從桌面助理到全日隨身全能助理（V2 → V3 → V4）

> 目的：定義 V1（現行桌面版）之後的完整版本階梯，直到最終形態——**開機即全日觀察（語音/影像）、持續摘要並理解主人的活動與個性、透過語音/眼鏡/手錶/耳機等先進介面全天提供協助、行為如 OpenClaw 般能與主人互動並套用最佳解決方案（TopAppSkills）的全能助理**。
> 方法論與 V1 相同（`docs/planning/implementation-backlog.md`）：切成可逐一交辦的 step、每步 TDD、區分 ✅ CI 可驗證與 🔒 需真機驗證、rolling-wave 展開。
> 使用方式：對我說「**完成 V2 step 3**」即可（V1 的 step 不加前綴，V2/V3 的加 `V2`/`V3` 前綴以免混淆）。
> 撰寫日期：2026-07-03。V4 章節涉及穿戴硬體，時效性最強，屆時需重新調研。

---

## 0. TL;DR

| 版本 | 代號 | 一句話 | 「跳出電腦」程度 |
|---|---|---|---|
| **V1**（現行） | CoPartner | 桌面 ambient 助理：看螢幕、寫劇本、熱鍵交棒 Claude 接手 | 0%——活在 Mac 裡 |
| **V2** | CoPartner **Listen** | 加上耳朵與嘴巴：全日音訊→本地轉錄→生活劇本；訊息閘道讓你**在任何地方**用手機跟它對話；語音交棒 | 30%——感知仍在桌邊，**互動**已隨身 |
| **V3** | CoPartner **Agent** | 加上手腳與主動性：技能引擎（TopAppSkills）、heartbeat 主動巡檢、手機/手錶衛星 app、信任階梯自動化 | 70%——感知與行動都隨身，眼睛仍受限 |
| **V4** | CoPartner **Omni** | 最終形態：眼鏡/墜飾/耳機穿戴優先、即時耳語協助、連續多模態感知、完整主人模型 | 100% |

**架構主軸（貫穿全部版本）：Hub-and-Satellites** —— Mac mini M4 永遠是**中樞（Hub）**：儲存、推理、閘道、技能執行都在這；手機、手錶、耳機、眼鏡都是**衛星**：感測器 + 介面，不存資料、不做重推理。這讓「本地優先、敏感不出境」的 V1 隱私承諾在每一版都成立——資料只是從「Mac 自己看到的」擴大到「衛星送回 Hub 的」，處理位置永遠不變。

---

## 1. 最終形態定義（North Star）

### 1.1 能力清單

最終的 CoPartner Omni 應能：

1. **全日感知**：醒著的時間裡持續聽（穿戴麥克風）、按需看（眼鏡相機/照片）、在電腦前看螢幕（V1）、讀行事曆/訊息/郵件（連接器）。
2. **持續理解**：把感知流即時壓成「生活劇本」（V1 操作劇本的全域化），滾動摘要成日誌，長期蒸餾成**主人檔案**——習慣、作息、人際、偏好、正在進行的專案與 open loops。
3. **對話互動**：任何時候、任何裝置（耳機語音、手錶、手機訊息、Mac）都能對話；它記得你們聊過什麼、你正在忙什麼，**不需要重新解釋脈絡**（V1 交棒哲學的全域化）。
4. **代理行動**：像 [OpenClaw](https://openclaw.ai/) 一樣接指令辦事——訂位、寄信、查資料、操作電腦（V1 takeover）——並套用 [TopAppSkills](https://github.com/pcpcchen-coder/TopAppSkills) 式的「完整解決方案」技能，而非零碎回答。
5. **主動性**：heartbeat 巡檢（行事曆衝突、未回訊息、routine 異常），在對的時機、對的裝置上輕推一下——但受打擾預算與信任階梯約束。
6. **隱私與信任**：本地優先；他人語音預設不留逐字稿；敏感永不出境（PIPL/PDPA）；每個自動化行為可稽核、可撤銷、可一鍵全停（kill-switch 從 V1 第一天就有）。

### 1.2 一天的樣子（設計錨點場景）

> 07:30 耳機說「早安。今天三個會，14:00 那個跟你昨晚在 Xcode 改的 WebSocket 重連有關——你上週答應 Ken 要 demo。昨天的日誌我放在手機上了。」
> 10:20 你在超商排隊，用手機打「幫我把 14:00 的會改到 15:00，跟 Ken 說一聲」。它改了行事曆、擬好訊息給你確認後送出。
> 14:55 會議中它聽到你說「這個我回去查一下」，默默記成 open loop。
> 18:00 你回到 Mac 前按熱鍵，它說「你下午說要查的是 X，我已經把相關文件找好了」——接手繼續（V1 takeover）。
> 23:00 它把今天壓成一段日誌，更新你的 ROUTINES.md（「週四晚上你通常在寫 side project」），然後睡覺。

每一版的驗收都回頭對照這個場景：該版本讓場景裡的哪幾句成真？

### 1.3 行為範本：OpenClaw 對應表

[OpenClaw](https://github.com/openclaw/openclaw)（self-hosted 個人 AI 助理閘道）已驗證了幾個關鍵機制，CoPartner 對應如下：

| OpenClaw 機制 | 內容 | CoPartner 對應 | 導入版本 |
|---|---|---|---|
| Messaging Gateway | 接 WhatsApp/Telegram/iMessage/Slack 等，用你已有的通訊軟體對話 | ChatGateway（Telegram 先行）| **V2** |
| Memory（markdown 檔）| 人類可讀、主人可編輯的記憶檔 | PROFILE.md / ROUTINES.md / PEOPLE.md / OPENLOOPS.md（生活劇本蒸餾層）| **V2** |
| Skills（ClawHub + Skill Card + SkillSpector 掃描）| 社群技能、來源卡、風險掃描 | SkillEngine 吃 TopAppSkills 格式 + 風險閘（沿用 V1 ActionExecutor 分級）| **V3** |
| Heartbeat（預設 30 分鐘讀 HEARTBEAT.md 主動巡檢）| 排程觸發的主動性 | ProactiveEngine + HEARTBEAT.md + 打擾預算 | **V3** |
| Host exec guardrails（2026-05 起 policy-first + human-in-loop）| 自動化的政策閘 | 信任階梯（suggest→confirm→auto per 技能類別）| **V3** |

差異：OpenClaw 的感知靠你「傳訊息給它」；CoPartner 的核心差異化是 **ambient 感知**（V1 螢幕 + V2 音訊 + V4 視覺）——它不用等你開口就知道脈絡。兩者互補，所以 V2 直接把 OpenClaw 式閘道抄進來，不重新發明。

### 1.4 技能庫：TopAppSkills 整合原則

[TopAppSkills](https://github.com/pcpcchen-coder/TopAppSkills)（你的 repo）＝ 100 個 markdown 技能，萃取自 App Store 20 類目前 100 名 app：每技能含 **System Prompt（300–800 字角色定義）、觸發條件、3–7 步工作流、Top 10 關鍵功能、UX 原則、輸出格式**，涵蓋社交娛樂/生產力/生活服務/金融購物四大類。

整合原則（V3 落地，V2 先把資料模型留好）：

1. **格式即介面**：SkillEngine 直接解析 TopAppSkills 的 markdown 結構（System Prompt / 觸發條件 / 工作流），不另造格式——repo 更新＝技能更新。
2. **觸發條件 → 意圖路由**：使用者訊息/語音先過意圖分類（本地 FM 3B，V1 已有此角色），比對技能觸發條件，選中技能後以其 System Prompt + 工作流組裝 agent prompt。
3. **風險分級沿用 V1**：技能宣告的動作過 ActionExecutor 的 Low/Medium/High 閘（V1 step 50/51）；金融購物類技能一律 confirm-each 起跳。
4. **技能安全掃描**：比照 OpenClaw SkillSpector——技能文本載入前掃 prompt-injection 樣式（「ignore previous instructions」類），第三方技能標示來源。

---

## 2. 版本階梯總覽

### 2.1 能力矩陣

| 維度 | V1 CoPartner | V2 Listen | V3 Agent | V4 Omni |
|---|---|---|---|---|
| **感知：螢幕** | ✅ foveated 擷取 | 沿用 | 沿用 | 沿用 |
| **感知：音訊** | — | ✅ Mac 端全日（桌邊）| 手機衛星麥克風（離桌）| 穿戴麥克風（全日）|
| **感知：視覺（鏡頭）** | — | — | 照片庫摘要（被動）| 眼鏡相機（主動按需）|
| **感知：數位足跡** | — | 行事曆（讀）| +郵件/訊息/位置 | 全連接器 |
| **認知：劇本** | 操作劇本 L0–L2 | **生活劇本**（螢幕+音訊統一時間軸）| +人物圖譜、routine 模型 | 完整主人模型 |
| **認知：記憶** | sqlite-vec 三層 | +Profile 蒸餾層（markdown）| +回饋學習（採納/拒絕）| 個人化持續精煉 |
| **行動** | 熱鍵交棒 computer-use | +訊息指令辦事（受限）| **技能引擎 + 主動 heartbeat** | 即時耳語協助 |
| **介面** | menu bar + 熱鍵 | +**Telegram/訊息** + Mac 語音 | +手機 app + 手錶 + 耳機語音 | +眼鏡/墜飾 |
| **隱私閘** | PII 遮罩+黑名單+PIPL | +他人語音政策+同意登錄 | +衛星端加密+遠端擦除 | +錄影同意機制 |
| **自動化信任** | confirm-each | confirm-each | **信任階梯**（分類別漸進 auto）| 高信任日常自動 |

### 2.2 為什麼是這個切法（版本邊界的邏輯）

- **V2 先給耳朵不給手腳**：全日音訊是「理解主人」最高密度的訊號（會議、通話、自言自語、環境），而且 Mac 端就能先做（桌邊 8–10 小時已覆蓋工作日大半），**不需要任何新硬體與新 app**。訊息閘道是「跳出電腦」成本最低的一步（一個 Telegram bot），先讓互動隨身，感知隨身留給 V3。
- **V3 才給手腳**：主動性與技能執行的前提是「它已經懂你」——沒有 V2 的生活劇本與 profile，主動建議只會是噪音。手機衛星 app 是大工程（iOS 背景音訊限制、電池），值得獨立一版。
- **V4 才碰穿戴**：眼鏡/墜飾硬體生態 2026 仍在快速變動（各家 SDK 開放程度不一），現在寫死是浪費；V4 的正確形式是「介面轉接層 + 屆時調研」。

### 2.3 與 V1 backlog 的銜接

- V1 的 58 步照舊進行（目前 step 1–9 ✅、step 10 🔒 待你 dogfood）。
- **V2 開工前置：V1 至少完成 Phase A（可跑骨架）+ Phase F（雲端交棒）**——因為 V2 的語音交棒（V2-E）直接掛在 F 的 ContextEnvelope/handoff 上。
- **例外（可穿插）**：V2-A（音訊管線）與 V2-E 的訊息閘道**不依賴 V1 的螢幕擷取**，若 V1 Phase B 卡在真機驗收等待期，可以穿插先做 V2-A 的純邏輯步——屆時明講即可。
- V1 backlog 文末「V3 展望」提到的語音項目，全數併入本文件的 **V2-E**（版本號重排：舊稱 V3 的語音 → 新階梯的 V2）。

---

## 3. 跨版本架構演化

### 3.1 Hub-and-Satellites

```
                    ┌─────────────────────────────────────────────┐
                    │        CoPartner Hub（Mac mini M4，常開）      │
                    │                                             │
  衛星（感測+介面）    │  [感知匯流] 螢幕(V1) 音訊(V2) 照片(V3) 鏡頭(V4) │
 ┌──────────┐ 加密   │      ↓                                      │
 │ iPhone    │ ────→ │  [生活劇本] L0 事件 → L1 敘事 → L2 情節       │
 │ Watch     │ 音訊/  │      ↓              ↓                       │
 │ AirPods   │ 語音/  │  [記憶] sqlite-vec 檢索層 + L3 日誌          │
 │ 眼鏡(V4)  │ 訊息   │         + L4 Profile 蒸餾（markdown，可編輯） │
 └──────────┘ ←──── │      ↓                                      │
   推播/語音回覆      │  [代理] 意圖路由 → SkillEngine(V3)            │
                    │         → 本地階梯/雲端(ADR-0007 EscalationPolicy)│
                    │         → ActionExecutor 風險閘(V1) + 信任階梯(V3)│
                    │  [閘道] ChatGateway(V2) / HTTP / 語音          │
                    │  [主動] ProactiveEngine + HEARTBEAT.md(V3)     │
                    └─────────────────────────────────────────────┘
```

原則：
1. **衛星無狀態**：衛星只做「擷取→壓縮→加密→送 Hub」與「呈現 Hub 的回覆」。掉了手錶不會掉資料。
2. **推理位置不變**：ADR-0007 的四層階梯（localOCR→localIntent→localVLM→cloud）整個活在 Hub；衛星永遠不直連雲端。新增第 0 層 `localASR`（語音轉文字，Hub 端 Whisper）。
3. **劇本是唯一事實來源**：所有感知源都匯進同一條生活劇本時間軸；所有介面都從同一份記憶回答。這是「不用重新解釋」體驗的技術本體。

### 3.2 資料模型演化：ActionStep → LifeEvent

V1 的 `ActionStep`（app/category/whatHappened/inferredGoal/confidence/artifacts/openLoop）已經是通用敘事單元，V2 起泛化：

```
LifeEvent（L1 敘事層的通用單元）
├─ source: screen | audio | calendar | message | photo | agent   ← 新增維度
├─ 既有欄位全保留（ActionStep 是 source=screen 的特例）
├─ participants: [PersonRef]      ← V2-B 說話人歸屬起
└─ location/context hint（可選） ← V3 衛星起

L0 音訊事件（V2 新增，與 V1 六種螢幕事件並列）：
  SAID    主人說話（逐字，PII 遮罩後）
  HEARD   他人說話（依政策：摘要 or 逐字-需同意 or 丟棄）
  CALL    通話段（起迄+參與者+摘要）
  MEETING 會議段（行事曆對齊）
  AMBIENT 環境聲語意標籤（音樂/電視/嘈雜），不存內容
```

### 3.3 記憶架構演化：加第四層「Profile 蒸餾」

V1 三層（RAM 熱劇本 / sqlite-vec 溫層 / SQLCipher 冷日誌）之上，V2 加 **L4 Profile 層**——借 OpenClaw 的 markdown 記憶檔設計，因為它有兩個無可取代的性質：**人類可讀可稽核**（你隨時能看它「以為你是誰」）與**主人可編輯**（寫錯了直接改）：

```
memory/profile/
├── PROFILE.md      我是誰：職業、專案、目標、偏好（它對你的長期理解）
├── ROUTINES.md     作息與習慣：「週四晚上通常寫 side project」
├── PEOPLE.md       人物誌：常互動的人、關係、上次聊什麼（PIPL 敏感→本檔永不出境）
├── OPENLOOPS.md    未完成事項：說過要做的、答應別人的
└── HEARTBEAT.md    (V3) 主動巡檢清單
```

蒸餾規則：L4 由 L2/L3 定期蒸餾（每日/每週），**每次變更產生 diff 進稽核日誌**；交棒/回答時 L4 作為穩定前綴（prompt cache 友善，延續 V1 §E 策略）。

### 3.4 信任階梯（V3 核心安全機制）

自動化程度**按技能類別分別漸進**，不是全域開關：

```
Level 0 suggest-only   （所有類別的起點）只建議，不動手
Level 1 confirm-each   每步確認（V1 takeover 現行模式）
Level 2 confirm-plan   確認計畫後整段執行，逐步可中止
Level 3 auto-bounded   預算/範圍內自動（如：回覆行事曆邀請），事後報告
─── 升級條件：該類別連續 N 次 confirm 你都按了同意 → 提議升級（你點頭才升）
─── 金融/購物/對外訊息類：上限 Level 2（硬限制）
─── kill-switch 永遠有效（V1 ⌃⌥⌘. + V2 遠端指令）
```

### 3.5 隱私、法律與倫理（全日音訊是全案最敏感的一步）

> ⚠️ 以下是工程設計原則，不是法律意見；正式部署（尤其涉及他人）前請諮詢律師。

1. **主人在場原則（owner-party rule）**：預設只處理「主人參與的對話」。VAD+說話人歸屬判定主人長時間未發聲且他人在談話 → 該段**不留逐字稿**（最多存「偵測到環境對話」）。依據：台灣刑法 315-1（竊錄他人非公開活動/談話）與通保法的一方同意原則——自己參與的對話錄音風險低，竊錄他人是刑事風險。
2. **他人語音三段政策**：(a) 未登錄者→只留「摘要級」描述（「與某人討論了專案時程」），不留逐字；(b) 同意登錄者（家人/同事，經 consent registry）→ 可逐字，但標記人物、預設不出境；(c) 上海團隊成員（PIPL）→ 逐字與摘要**一律 local-only**，PEOPLE.md 相關條目永不進雲端 prompt（沿用 ADR-0005/0007 隱私閘門，`containsSensitive` 訊號源多一個「參與者含 PIPL 對象」）。
3. **場景抑制**：通話/會議 app 偵測（Zoom/Teams/FaceTime 前景）→ 依會議政策（預設摘要級）；使用者定義的抑制時段/地點（V3 起有位置）；**實體靜音鍵**（menu bar 一鍵 + 熱鍵 + 之後穿戴實體鍵）優先級最高。
4. **保存分層**：原始音訊**用後即焚**（轉錄完成即刪，預設不留 raw audio）；逐字稿 7–30 天（可設）；L2 摘要 90 天；L3/L4 長期（加密）。所有層可主人一鍵擦除（「忘掉今天下午」）。
5. **出境規則不變**：雲端只收「劇本文字（遮罩後）+ 必要焦點圖」；音訊波形永不出境；轉錄先過 PIIMasker（V1 step 7 直接重用）再進劇本。
6. **倫理紅線**：不對他人做聲紋識別資料庫（只有 owner 聲紋 + 明示同意的登錄者）；家庭共用空間提供「訪客模式」（一鍵暫停感知）；V4 眼鏡錄影遵守當地法規 + 錄製指示燈。

---

## 4. V2 — CoPartner Listen：詳細規劃與 TDD Backlog

**版本目標**：V2 結束時，(1) Mac 桌邊全日音訊→本地轉錄→與螢幕劇本合流成**生活劇本**，每晚產出日誌；(2) 你可以**從手機 Telegram** 問它「我今天做了什麼」「上週二下午我在忙什麼」並得到正確回答、收到每日文摘推播、遠端下 kill-switch；(3) Mac 端 push-to-talk **語音交棒**（對它說話→接手，V1 熱鍵交棒的語音版）。
**明確不做**（留 V3）：手機端錄音、主動建議、技能執行、手錶/耳機。
**估時**：~16–20 週（5–10 hr/週，V1 完成後起算）。

### 4.0 V2 技術選型（開工前可再驗證）

| 元件 | 選型 | 理由 | 備援 |
|---|---|---|---|
| ASR | `mlx-whisper`（large-v3-turbo 或 distil 系列，M4 GPU）| sidecar 已是 Python/MLX 生態（與 Qwen 同棧）；桌邊串流延遲可接受 | whisper.cpp（CoreML）|
| VAD | 能量門檻狀態機（Swift，可測）+ `silero-vad`（sidecar 精判）| 兩段式：便宜的先擋，貴的精判——與 V1「SCK 主訊號+Metal 驗證」同構 | 只用能量門檻 |
| 說話人 | sidecar speaker-embedding（ecapa/pyannote 系）+ Swift 端 turn 合併邏輯 | 只需要「owner vs 非 owner vs 已登錄者」，不需完整 diarization 品質 | 只分 owner/非 owner |
| 敘事 | FoundationModels 3B（V1 M4 的同一套 + fallback 階梯）| 音訊 L1 與螢幕 L1 是同一件事 | Qwen / 規則模板 |
| 閘道 | Telegram Bot API | 免費、API 乾淨、有 long-poll（不用公網 webhook）；OpenClaw 生態驗證過訊息閘道模式 | Discord / LINE Notify |
| 行事曆 | EventKit（讀）| 會議段對齊 + 日誌豐富化 | 手動略過 |

### 4.1 進度總覽（V2 step 1–36）

| # | Step | 階段 | 建議模型 | 狀態 | 前置 |
|---|---|---|---|---|---|
| **V2-A. 音訊管線基礎（Mac 端）** ||||||
| 1 | 音訊資料模型（AudioChunk/TranscriptSegment） | A | Sonnet 5 | ⬜ | V1 完成（見 §2.3）|
| 2 | 能量門檻 VAD 狀態機 | A | Sonnet 5 | ⬜ | 1 |
| 3 | 環形緩衝與分段器（chunker） | A | Sonnet 5 | ⬜ | 2 |
| 4 | sidecar `/asr` 端點（mlx-whisper）+ 合約測試 | A | Opus 4.8 | ⬜ | 1 |
| 5 | Swift ASRClient + 退壓/重試邏輯 | A | Sonnet 5 | ⬜ | 3,4 |
| 6 | 轉錄合併器（overlap dedup + 正規化） | A | Sonnet 5 | ⬜ | 5 |
| 7 | AVAudioEngine 擷取膠水（🔒 麥克風 TCC） | A | Sonnet 5 | ⬜ | 3 |
| 8 | 🔒 桌邊 8hr 試錄驗收（CPU/磁碟/WER 抽查） | A | — | ⬜ | 6,7 |
| **V2-B. 說話人歸屬與隱私閘門** ||||||
| 9 | 【展開】B 階段細部規劃 | B | Opus 4.8 | ⬜ | 8 |
| 10 | Owner 聲紋註冊狀態機（+ 🔒 embedding 膠水） | B | Opus 4.8 | ⬜ | 9 |
| 11 | 說話人 turn 合併（embedding→speaker-tagged segments） | B | Sonnet 5 | ⬜ | 10 |
| 12 | 他人語音三段政策執行器（隱私關鍵） | B | **Fable 5 設計 / Opus 審** | ⬜ | 11 |
| 13 | 同意登錄表 + 場景抑制規則（會議 app/時段/靜音鍵） | B | Opus 4.8 | ⬜ | 12 |
| 14 | 🔒 說話人歸屬真機品質驗收 | B | — | ⬜ | 11,12,13 |
| **V2-C. 生活劇本：統一時間軸** ||||||
| 15 | 【展開】C 階段細部規劃 | C | Opus 4.8 | ⬜ | 14 |
| 16 | L0 音訊事件型別 + EventFormatter 擴充 | C | Sonnet 5 | ⬜ | 15 |
| 17 | LifeEvent 泛化（ActionStep 加 source/participants） | C | Sonnet 5 | ⬜ | 15 |
| 18 | 統一時間軸合併器（螢幕+音訊排序/去重/會話邊界） | C | Opus 4.8 | ⬜ | 16,17 |
| 19 | 行事曆對齊（EventKit 讀取 🔒 + MEETING 段落邏輯 ✅） | C | Sonnet 5 | ⬜ | 18 |
| 20 | L1 音訊敘事 rollup 觸發規則（FM 呼叫沿用 V1-M4 階梯） | C | Sonnet 5 | ⬜ | 18 |
| 21 | L3 每日文摘產生器（結構 ✅ / 文字品質 🔒） | C | Sonnet 5 | ⬜ | 20 |
| 22 | 🔒 一日生活劇本驗收（音訊版時間機器） | C | — | ⬜ | 19,20,21 |
| **V2-D. 記憶擴充與 Owner Profile v0** ||||||
| 23 | 【展開】D 階段細部規劃 | D | Opus 4.8 | ⬜ | 22 |
| 24 | Routine 偵測（合成時間軸的週期樣態挖掘） | D | Opus 4.8 | ⬜ | 23 |
| 25 | 人物圖譜 v0（說話人+行事曆參與者合併） | D | Sonnet 5 | ⬜ | 23 |
| 26 | Profile 蒸餾器（PROFILE/ROUTINES/PEOPLE/OPENLOOPS.md + 變更 diff 稽核） | D | Opus 4.8 | ⬜ | 24,25 |
| 27 | 記憶檢索整合（生活劇本+profile 進 sqlite-vec；時間/語意查詢路由） | D | Opus 4.8 | ⬜ | 26 |
| **V2-E. 訊息閘道與語音交棒（跳出電腦）** ||||||
| 28 | 【展開】E 階段細部規劃 | E | Opus 4.8 | ⬜ | 27 |
| 29 | ChatGateway 抽象層 + 指令路由器 | E | Sonnet 5 | ⬜ | 28 |
| 30 | Telegram bot 接線（long-poll 🔒 + 路由合約測試 ✅） | E | Sonnet 5 | ⬜ | 29 |
| 31 | 查詢指令（「今天做了什麼」→記憶檢索→回答） | E | Sonnet 5 | ⬜ | 27,30 |
| 32 | 每日文摘推播 + 安靜時段 | E | Sonnet 5 | ⬜ | 21,30 |
| 33 | 遠端 kill-switch（訊息指令停止/恢復觀察，安全關鍵） | E | Opus 4.8 | ⬜ | 30 |
| 34 | Mac push-to-talk 語音交棒（熱鍵按住說話→STT→ContextEnvelope→V1 handoff） | E | Opus 4.8 | ⬜ | 4, V1-F |
| **V2-F. 隱私固化與總驗收** ||||||
| 35 | 保存期限引擎（用後即焚/分層 age-out/一鍵擦除）+ PIPL 音訊補遺文件 | F | **Opus 4.8** | ⬜ | 13,27 |
| 36 | 🔒 V2 總驗收（一週 dogfood + 隱私稽核清單） | F | — | ⬜ | 全部 |

### 4.2 V2-A 完整展開（可直接開工的 TDD 規格）

#### V2 Step 1 — 音訊資料模型
- **新增**（`CoPartnerCore`）：`AudioChunk`（id/startAt/duration/sampleRate/能量統計，**不含波形**——波形只活在擷取層記憶體）、`TranscriptSegment`（chunkID/text/speaker: `.owner|.enrolled(PersonRef)|.unknown`/confidence/startAt/endAt）、`SpeakerLabel` enum。全部 `Sendable+Codable`。
- **測試**（`AudioModelsTests.swift`）：Codable round-trip；segment 時間區間不變式（end≥start）；speaker label 的 Codable 對 unknown 個資零洩漏（encode 後不含人名欄位）。
- **DoD**：✅ CI ・ **模型**：Sonnet 5

#### V2 Step 2 — 能量門檻 VAD 狀態機
- **新增**（`CaptureEngine` 或新 target `AudioEngine`——開工時定，傾向新 target 以免混淆螢幕/音訊）：`EnergyVAD` 純狀態機——輸入（能量值, now）序列，輸出 `speechStarted/speechEnded` 事件。參數：開啟門檻、關閉門檻（遲滯 hysteresis）、最短語音長度（去 click）、尾音延遲 hangover（0.5–1s，避免句中停頓被切）。
- **測試**（`EnergyVADTests.swift`）：安靜→無事件；超過門檻連續 N ms→speechStarted；掉到關閉門檻以下 hangover 後→speechEnded；句中短停頓（<hangover）不切段；突波（<最短長度）被忽略；遲滯（開>關門檻）防抖動。全部合成能量序列 + 注入時間，決定性。
- **DoD**：✅ CI ・ **模型**：Sonnet 5

#### V2 Step 3 — 環形緩衝與分段器
- **新增**：`AudioChunker`——吃 VAD 事件流 + 樣本計數，產出 `AudioChunk` 邊界：語音段結束→切 chunk；語音持續超過 maxChunkSeconds（如 30s）→強制切（ASR 有輸入長度上限）；保留前導 preroll（0.3s，避免吃掉字頭）。
- **測試**：一段完整語音→一個 chunk 含 preroll；超長語音→多 chunk 且邊界重疊 overlapSeconds；靜音期間零 chunk；chunk 時間戳與 VAD 事件對齊。
- **DoD**：✅ CI ・ **模型**：Sonnet 5

#### V2 Step 4 — sidecar `/asr` 端點
- **修改**（`sidecar/`）：新增 `/asr` endpoint（輸入 wav/pcm 路徑或 base64 + 語言 hint zh/en，輸出 segments[text/start/end/confidence]）。mlx-whisper 載入採 lazy + 單例（模型 ~1.5GB 記憶體駐留）。**測試策略**：pytest 用 **fake model 注入**（protocol：`transcribe(audio)->segments`）測 API 合約/錯誤處理/超時，真模型推理標 🔒（CI runner 拉不動大模型權重；V1 step 28 建立的 pytest job 跑合約測試）。
- **測試**（`sidecar/tests/test_asr.py`）：合約 schema、空音訊 400、超長音訊 413、fake model 回傳正確映射、模型未載入時 503。
- **DoD**：合約 ✅ CI（pytest）；真轉錄品質 🔒（V2 step 8）・ **模型**：Opus 4.8（串流/記憶體管理易踩坑）

#### V2 Step 5 — Swift ASRClient
- **新增**：`ASRClient`（protocol `ASRService` + HTTP 實作）——chunk 佇列、序列化送 sidecar、退壓（佇列>N 時降級：丟 AMBIENT 標籤不轉錄）、重試（指數退避，沿用 git push 的 2/4/8s 模式）、sidecar 掛掉→劇本記「聽寫暫停」事件而非靜默丟失。
- **測試**：假 `ASRService` 驗證佇列順序、退壓觸發、重試次數、失敗降級事件。
- **DoD**：✅ CI ・ **模型**：Sonnet 5

#### V2 Step 6 — 轉錄合併器
- **新增**：`TranscriptMerger`——相鄰 chunk overlap 區的重複文字去重（最長共同後綴/前綴比對）、whisper 幻覺樣式過濾（重複 n-gram 循環、空白段的「謝謝觀看」類已知幻覺清單）、中英混排空白正規化。
- **測試**：golden cases——overlap 重複去除、幻覺清單命中過濾、正常文本不誤傷、中英混排間距。
- **DoD**：✅ CI ・ **模型**：Sonnet 5

#### V2 Step 7 — AVAudioEngine 擷取膠水（🔒）
- **新增**：`MicrophoneSource`——AVAudioEngine tap、16kHz 單聲道重採樣、能量計算餵 VAD、麥克風 TCC 權限請求、預設裝置變更處理（換耳機）。介面對齊 `AudioChunker`。**Info.plist 加 `NSMicrophoneUsageDescription`**。
- **DoD**：編譯 ✅ CI；實際擷取 🔒（step 8）・ **模型**：Sonnet 5

#### V2 Step 8 — 🔒 桌邊 8hr 試錄驗收
- 你在 Mac 上跑一個工作日：CPU 增量（目標 <10% 平均）、磁碟（轉錄文字 <5MB/日；raw audio 用後即焚確認真的沒留）、WER 抽查（隨機 10 段人工比對）、風扇/溫度體感。回報數字，決定 whisper 模型尺寸調整。

### 4.3 V2-B ～ V2-F 規格摘要（各階段【展開】步會補到 V2-A 等級）

- **V2 Step 10 聲紋註冊**：狀態機——引導錄 N 段→embedding 平均→門檻校準（FAR/FRR 平衡）→存 Keychain。測試：狀態轉換、樣本不足拒絕完成、門檻計算。embedding 計算在 sidecar（🔒）。
- **V2 Step 12 三段政策執行器**（全 V2 隱私核心，比照 V1 PIIMasker 的嚴格度）：輸入 speaker-tagged segments + 同意登錄表 → 輸出「入劇本形式」：owner→逐字（過 PIIMasker）；enrolled+consented→逐字+標人；unknown→**丟棄逐字**，只產 HEARD 摘要事件；PIPL 對象→逐字強制 local-only 標記（`containsSensitive=true` 進 ADR-0007 訊號）。測試：四類輸入的輸出形式各自正確、**逐字稿在 unknown 路徑上真的不存在於任何輸出**（防洩漏斷言）、政策參數化。
- **V2 Step 18 統一時間軸合併器**：螢幕 LifeEvent 與音訊 LifeEvent 依時間戳穩定排序、會話邊界（>N 分鐘空檔切 episode）、同事件跨源去重（會議中打字：螢幕 TYPE 與音訊 MEETING 並存不互吃）。測試用合成雙源時間軸。
- **V2 Step 24 Routine 偵測**：對合成 4 週時間軸驗證——「每週四 21:00±45min 出現 coding episode ≥3 次 → routine 候選」；缺席不誤報；置信度隨重複次數上升。
- **V2 Step 26 Profile 蒸餾器**：L2/L3 → 四份 markdown 的**結構化更新**（append/update/expire 規則），每次變更產生 diff 記錄。測試：diff 正確性、過期規則、**PEOPLE.md 中 PIPL 標記者的條目帶 local-only 標頭**。
- **V2 Step 29 ChatGateway**：`protocol ChatGateway`（send/receive/typing）+ `CommandRouter`（訊息→意圖：查詢/控制/交棒/閒聊）——路由決策純邏輯可測；Telegram 是第一個實作（step 30）。
- **V2 Step 33 遠端 kill-switch**：指令文法（`/stop` `/resume` `/status`）、**冪等**、需確認的破壞性指令（`/wipe today`）二段確認。測試：狀態機 + 未授權 chat id 拒絕（**只回應 owner 的 chat id**，防他人指揮你的助理）。
- **V2 Step 34 語音交棒**：按住熱鍵→錄音→`/asr`→文字併入 TakeoverContract.instruction→V1 handoff 流程。狀態機（idle/recording/transcribing/handing-off/aborted）可測；端到端 🔒。
- **V2 Step 35 保存期限引擎**：分層 TTL 排程（邏輯時鐘注入可測）、「忘掉今天下午」時間範圍擦除（劇本+向量+profile 三處一致刪除）、擦除稽核記錄。

### 4.4 V2 驗收（對照 §1.2 場景）

| 場景句 | V2 後成真？ |
|---|---|
| 「昨天的日誌我放在手機上了」 | ✅（Telegram 每日文摘）|
| 超商排隊用手機問它/叫它辦事 | 🟡 問答✅；「改行事曆+傳訊息」等辦事是 V3 技能 |
| 會議中聽到「我回去查一下」記成 open loop | ✅（桌邊會議；離桌會議要 V3 手機衛星）|
| 回 Mac 按熱鍵它知道下午說過什麼 | ✅（生活劇本進交棒 envelope）|
| 早晨耳機主動簡報 | ❌ V3（主動性+耳機）|

---

## 5. V3 — CoPartner Agent：規劃與 Backlog（rolling-wave）

**版本目標**：(1) **技能引擎**——TopAppSkills 100 技能可被意圖路由選中並在風險閘下執行，行為如 OpenClaw（含技能安全掃描與來源標示）；(2) **主動性**——heartbeat 讀 HEARTBEAT.md 巡檢（行事曆衝突/未回訊息/open loops/routine 異常），受打擾預算與安靜時段約束；(3) **隨身衛星**——iPhone companion app（衛星麥克風+推播+語音對話）、Watch 快捷、AirPods 語音；(4) **信任階梯**——分類別 suggest→confirm→auto 漸進自動化。
**估時**：~18–24 週。開工前置：V2 完成。

| # | Step | 階段 | 模型 | 前置 |
|---|---|---|---|---|
| V3-1 | 【展開】A 技能引擎細部規劃 + 威脅模型（prompt injection/技能供應鏈） | A | **Fable 5** | V2 |
| V3-2 | TopAppSkills manifest 解析器（markdown→SkillCard 結構）| A | Sonnet 5 | 1 |
| V3-3 | 技能安全掃描器（injection 樣式/未宣告動作偵測，比照 SkillSpector）| A | Opus 4.8 | 2 |
| V3-4 | 意圖→技能路由（觸發條件比對 + 本地 FM 分類，含「無技能」fallback）| A | Opus 4.8 | 2 |
| V3-5 | 技能執行器（System Prompt+工作流組裝→agent 迴圈→ActionExecutor 風險閘）| A | **Fable 5** | 3,4 |
| V3-6 | 技能結果稽核與回饋記錄（成功/失敗/使用者修正）| A | Sonnet 5 | 5 |
| V3-7 | 🔒 技能真機驗收（10 個代表性技能端到端）| A | — | 5,6 |
| V3-8 | 【展開】B 主動性引擎細部規劃 | B | Opus 4.8 | 7 |
| V3-9 | Heartbeat 排程器 + HEARTBEAT.md 解析（間隔/條件/靜默規則）| B | Sonnet 5 | 8 |
| V3-10 | 觸發規則庫（行事曆衝突/未回訊息/open loop 到期/routine 異常）| B | Opus 4.8 | 9 |
| V3-11 | 打擾預算與通知路由（每日上限/安靜時段/裝置選擇/重要度分級）| B | Opus 4.8 | 10 |
| V3-12 | 建議回饋學習（採納/忽略/拒絕→調整該類觸發閾值）| B | Opus 4.8 | 11 |
| V3-13 | 【展開】C 隨身衛星細部規劃（iOS 背景音訊策略是最大風險，先 spike）| C | **Fable 5** | 7 |
| V3-14 | Hub↔衛星同步協定（加密 journal 複製、斷線重連、時鐘偏移）| C | **Fable 5** | 13 |
| V3-15 | iPhone companion app v0（推播+文字對話+狀態）| C | Sonnet 5 | 14 |
| V3-16 | iPhone 衛星麥克風（前景/可行範圍內背景錄音→壓縮→送 Hub）| C | Opus 4.8 | 15 |
| V3-17 | Watch 快捷 + AirPods 語音對話 | C | Sonnet 5 | 15 |
| V3-18 | 遠端擦除與衛星撤銷（掉裝置情境）| C | Opus 4.8 | 14 |
| V3-19 | 【展開】D 信任階梯細部規劃 | D | Opus 4.8 | 7 |
| V3-20 | 信任階梯政策引擎（分類別等級/升級提議/硬上限/全域降級）| D | **Fable 5 設計 / Opus 審** | 19 |
| V3-21 | 個性與語氣適配（PROFILE.md→回覆風格；正式/簡潔/幽默偏好）| D | Sonnet 5 | 19 |
| V3-22 | 🔒 V3 總驗收（兩週 dogfood：主動建議品質+衛星電池+技能成功率）| — | — | 全部 |

TDD 原則不變：manifest 解析、路由決策、heartbeat 規則、打擾預算、信任階梯、同步協定狀態機全是純邏輯 ✅；iOS 背景音訊、APNs、Watch/AirPods 是 🔒。**V3-13/14（衛星同步）與 V3-5（技能執行器）是全 V3 的 Fable 5 級難題**——前者是分散式狀態，後者是安全邊界。

---

## 6. V4 — CoPartner Omni：最終形態（里程碑級，屆時展開）

穿戴硬體生態變動太快，V4 只定**里程碑與決策點**，開工前重新調研：

| 里程碑 | 內容 | 關鍵決策點 |
|---|---|---|
| O1 介面轉接層 | `WearableAdapter` protocol：音訊進/語音出/顯示出（可選）/實體鍵，讓任何穿戴裝置以統一介面接 Hub | 首發裝置選型：智慧眼鏡（顯示+相機）vs 錄音墜飾（最輕）vs 純 AirPods（零新硬體）——依 2027–28 生態決定 |
| O2 全日穿戴音訊 | V2 音訊管線的輸入源從 Mac 麥克風換成穿戴（經衛星協定）；電池/頻寬預算 | 裝置端 VAD（省電關鍵）能否在裝置 SDK 內跑 |
| O3 即時耳語協助 | <2s 延遲的「聽到→理解→耳邊提示」迴路（會議中提醒、對話中補充資訊）| 延遲預算切分（裝置→Hub→推理→回傳）；哪些場景值得打斷 |
| O4 視覺感知 | 眼鏡相機按需拍照→localVLM（ADR-0007 現成階梯）；錄影同意機制（指示燈/地理圍欄） | 法規與社交接受度；預設拍照不錄影 |
| O5 完整主人模型 | Profile 層升級為可自我修正的長期模型；跨年度記憶壓縮 | 個人化 fine-tune vs 純 context（傾向純 context + 蒸餾文件，可稽核）|
| O6 家庭禮儀 | 多人空間偵測、訪客模式自動化、家人裝置互認 | 多 owner 支援與否（傾向單 owner + 禮儀，不做多租戶）|

---

## 7. 開發模型分工與成本（延續 `dev-execution-plan.md` 策略）

**開發時**（Claude Code）：分工邏輯不變——Sonnet 5 日常主力（~75%）、Opus 4.8 起手/除錯/審查/隱私關鍵（~20%）、Fable 5 只留給無先例難題（~5%）：V2 的三段政策設計（step 12）、V3 的技能執行器（V3-5）、衛星同步協定（V3-14）、信任階梯設計（V3-20）、V4 即時迴路。訂閱建議不變（Max 5x 為主、難題月升 20x）。

**執行時**（產品本身的推理成本）：

| 工作 | 引擎 | 邊際成本 |
|---|---|---|
| 全日 ASR | mlx-whisper @ Hub | $0（電費；M4 GPU 桌邊綽綽有餘）|
| VAD/說話人 | 本地 | $0 |
| L1/L2 敘事 | FoundationModels 3B | $0 |
| 每日文摘 L3 | 本地為主；可選雲端潤飾 | ~$0–0.1/日 |
| 訊息問答 | 本地檢索+FM；複雜才升雲（ADR-0007）| 低 |
| 技能執行/交棒 | 雲端 Claude（現行 LiteLLM $5/日熔斷沿用）| 受控 |

結論：**全日感知的邊際成本設計為 $0**（全本地），雲端只花在「你主動要它做事」的時刻——這是 Hub 架構的經濟本質，也是跟訂閱制穿戴助理服務的根本差異。

---

## 8. 時程總覽（solo 5–10 hr/週，保守）

| 版本 | 估時 | 日曆（假設 V1 於 2026-12 完成）|
|---|---|---|
| V1 剩餘（step 10–58）| ~20 週 | → 2026-12 |
| **V2 Listen**（36 steps）| 16–20 週 | 2027-01 → 2027-05/06 |
| **V3 Agent**（22 steps）| 18–24 週 | 2027-06 → 2027-11/2028-01 |
| **V4 Omni** | 開放（硬體依賴）| 2028+，O1–O3 約再半年 |

緩衝原則同 V1：每版結束重新校準下一版估時；穿插真機驗收等待期可預抓下一階段純邏輯步。

## 9. 風險與待驗證假設（誠實清單）

1. **iOS 背景錄音限制（V3 最大技術風險）**：iOS 對背景麥克風限制嚴格，「手機當全日衛星麥克風」可能只在前景/CarPlay/特定模式可行。緩解：V3-13 先做 spike；備援＝錄音墜飾類硬體提前到 V3。
2. **Whisper 中英混排品質**：你的環境是中英混雜（code+中文），WER 假設待 V2 step 8 實測；備援＝語言 hint 分段 + 更大模型。
3. **說話人歸屬在真實環境的精度**：桌邊多人+回音+鍵盤聲；V2 的政策設計已假設歸屬會出錯（unknown 預設丟逐字＝錯也錯在安全側）。
4. **全日音訊的心理/社交成本**：同事/家人對「你戴著錄音的東西」的觀感；§3.5 的同意與訪客模式是工程答案，但實際接受度要 dogfood 驗證——**這是 V2 step 36 一週 dogfood 的隱藏驗收項**。
5. **法律**：§3.5 為工程原則非法律意見；跨境（上海團隊）與公共空間錄影（V4）前應諮詢律師。
6. **OpenClaw/TopAppSkills 演進**：兩者都在快速迭代；V3-1 展開時重新對齊當時格式（本文引用為 2026-07 快照）。
7. **單人開發的長征風險**：V2+V3 合計約一年。緩解＝每版都設計成「該版結束即有完整可用產品」，不是半成品接力——V2 停下來也是一個完整的「聆聽日誌助理」。

## 10. 參考來源

- [OpenClaw 官網](https://openclaw.ai/)・[OpenClaw docs](https://docs.openclaw.ai/start/openclaw)・[openclaw/openclaw（GitHub）](https://github.com/openclaw/openclaw)——訊息閘道、markdown 記憶、skills/ClawHub/SkillSpector、heartbeat、guardrails 機制參考（2026-07 快照）。
- [TopAppSkills（pcpcchen-coder）](https://github.com/pcpcchen-coder/TopAppSkills)——100 個 markdown 技能：System Prompt/觸發條件/工作流/關鍵功能/UX 原則/輸出格式，四大類（社交娛樂/生產力/生活服務/金融購物）。
- 本 repo：`docs/design/`（V1/V2/V2.1 設計）、`docs/adr/0005~0007`（隱私邊界與分層推理——V2+ 全數沿用）、`docs/planning/implementation-backlog.md`（V1 的 58 步方法論範本）。
