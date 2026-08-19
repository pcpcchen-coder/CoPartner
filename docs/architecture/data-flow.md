# 資料流

兩條路徑：**常時觀察**（一直在跑）與**接手**（熱鍵觸發）。

## 常時觀察

```mermaid
flowchart LR
    Input["輸入事件<br/>CGEventTap"] --> L0
    Focus["焦點變化<br/>NSWorkspace + AX"] --> L0
    Screen["螢幕<br/>SCStream"] --> Tiles["dirty tile<br/>Metal dHash"]
    Tiles --> OCR["局部 OCR<br/>macOS Vision"]
    OCR --> L0

    L0["L0 事件日誌<br/>human-readable、deterministic"]
    L0 --> Rollup{"L1RollupScheduler<br/>該叫模型了嗎"}
    Rollup -->|"app 邊界 / 行數 / 間隔"| L1["L1 敘事步驟<br/>本地 3B"]
    Rollup -->|"否"| L0
    L1 --> Hot["熱環<br/>L1HotBuffer"] --> L2["L2 段落摘要"]
    L1 --> Mem["MemoryStore"]
```

**兩個容易踩的地方**（都真機踩過）：

- **新活動偵測不能用行數差**。`EventLog.record` 會就地改寫最後一行（打字合併、捲動聚合），
  而 `EventLogFeed` 是 ring buffer——兩者各自都足以讓行數差永久歸零。改用 `(行數, 末行內容)` 指紋。
- **視窗標題不是視窗身分**。終端機把尺寸寫進標題、AX 有時整個讀不到、
  而 app 名稱與標題來自兩個獨立來源、切換瞬間會不同步。詳見 `FocusChangeTracker` 檔頭的四次教訓。

## 接手

```mermaid
sequenceDiagram
    autonumber
    participant U as 使用者
    participant App as CoPartner.app
    participant Gate as EgressGate
    participant C as Claude
    participant HUD as 確認 HUD
    participant X as XPC service

    U->>App: ⌃⌥⌘Space
    App->>App: 打包 ContextEnvelope（L1 步驟 + open loop）
    App->>Gate: 出境檢查
    alt PIPL 命中
        Gate--xApp: 整包拒出，僅本地處理
    else 通過
        Gate->>C: 遮罩後的 envelope
        loop 每個提議
            C-->>App: tool_use（SSE 串流）
            App->>App: 本地風險分級（與模型推理無關）
            alt 低風險且 autoBounded
                App->>App: 自動核准，鑄造 ApprovalToken
            else 其餘（含全部高風險）
                App->>HUD: 顯示本地產生的動作原文 + 風險原因
                HUD-->>U: 執行 / 略過 / 停止
                U-->>HUD: 決定
            end
            App->>X: 已核准的結構化 argv
            X-->>App: 結果（目前一律「收到但沒做」）
        end
    end
    Note over U,X: ⌃⌥⌘. 隨時可撥世代時鐘 → 串流斷、在途 token 全失效
```

⚠️ 圖中最後一步目前**刻意**是「收到但沒做」：執行能力尚未開啟（backlog step 53.5）。
佔位一律 throw、絕不靜默假裝成功——否則後面每一次驗收都建立在一個假的成功上。

## 信任邊界

```mermaid
flowchart TD
    B0["螢幕上的一切<br/>網頁 / 信件 / PDF"]:::untrusted
    B0 -->|"B0：不可信輸入"| Script["劇本 / OCR / AX"]
    Script --> Env["ContextEnvelope"]
    Env -->|"B1：出境閘門<br/>PII 遮罩 + PIPL 硬牆"| Cloud["Claude（雲端）"]:::untrusted
    Cloud -->|"B2：模型輸出＝不可信提議"| Proposals["ProposedAction 流"]
    Proposals -->|"B3：本地風險分級<br/>+ 人工確認（ApprovalToken）"| Approved["已核准動作"]
    Approved -->|"B4：deny-default sbpl"| Mac["使用者的 Mac"]

    classDef untrusted fill:#3b1f1f,stroke:#a33,color:#fdd
```

**核心立場**：防線不依賴「模型乖」。B0 假設螢幕內容含針對 AI 的注入指令；
B2 假設模型即使沒被注入也會犯錯。真正擋住事情的是 B3 與 B4 這兩道**本地硬邊界**。

威脅列舉（T1–T10）與可測不變式（I1–I10）見
[`sandbox-threat-model.md`](../design/sandbox-threat-model.md)。
