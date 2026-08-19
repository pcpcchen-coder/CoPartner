# 架構總覽

> 圖表一律用 **Mermaid**：純文字、可 diff、GitHub 直接算圖，改一行就好。

CoPartner 是混合式（本地 + 雲端）ambient AI 代理。三大支柱：

1. **Smart Capture Engine**（`CaptureEngine`）— foveated / dirty-region 螢幕擷取。
2. **Action Script Narrator**（`ScriptNarrator`）— 本地模型把操作寫成滾動劇本。
3. **Cloud Takeover**（`CloudRouter` + `ActionExecutor`）— 熱鍵觸發時交棒給 Claude 續寫。

## 模組相依

實線＝相依；所有模組只共用 `CoPartnerCore` 的值型別，彼此不互相 import。
這是刻意的：模組之間若能互相引用，「純邏輯」與「平台膠水」的界線很快就會被磨掉。

```mermaid
flowchart TD
    App["CoPartner.app<br/>SwiftUI menu bar"]
    Exec["CoPartnerExecutor<br/>XPC service"]

    subgraph Kit["packages/CoPartnerKit — 所有可測邏輯"]
        Core["CoPartnerCore<br/>共用值型別"]
        Capture["CaptureEngine<br/>SCK + Metal tile hash"]
        Narrator["ScriptNarrator<br/>L0/L1/L2 敘事"]
        Memory["MemoryStore<br/>三層記憶"]
        Router["CloudRouter<br/>交棒與 SSE 解碼"]
        Executor["ActionExecutor<br/>風險分級 / 閘門 / 沙箱政策"]
    end

    App --> Capture & Narrator & Memory & Router & Executor
    Exec --> Executor
    Capture & Narrator & Memory & Router & Executor --> Core
    App <-.->|"XPC（結構化 argv）"| Exec
```

## 為什麼可測邏輯全在 CoPartnerKit

開發代理跑在 **沒有 Mac、沒有螢幕、沒有權限**的 Linux 容器裡，所以平台膠水一律盲寫、
只能靠真機 dogfood 驗。應對方式是把界線畫在「CI 驗得到」與「只有真機驗得到」之間：

```mermaid
flowchart LR
    subgraph CI["CI 驗得到（純值 / 可注入假後端）"]
        L1["風險分級<br/>危險指令偵測"]
        L2["ApprovalToken 閘門<br/>世代作廢"]
        L3["sbpl profile 產生<br/>路徑跳脫與解析"]
        L4["線上契約編解碼<br/>argv 邊界"]
    end
    subgraph Device["🔒 只有真機驗得到"]
        D1["ScreenCaptureKit / Metal"]
        D2["FoundationModels 推理"]
        D3["XPC 連線與驗簽"]
        D4["sandbox-exec 實際套用"]
    end
    CI -->|"protocol 注入"| Device
```

**判準**：如果一段程式碼的正確性取決於「餵給平台 API 的參數」，它就該在 CI 那一側——
`posix_spawn` 本身不會出錯，錯的是我們給它什麼。

## 橫切關注

| 關注 | 落點 |
|---|---|
| 隱私閘門 | `PIIMasker`（L0 文字）、`TileMaskPolicy`（像素）、`CaptureBlacklist`（app 源頭）、`EgressGate`（出境 PIPL 硬牆）|
| kill-switch | `HandoffGeneration` 世代時鐘——一撥全鏈作廢（串流、token、executor）|
| 稽核 | `ActionExecutor.auditLog`，attempt / executed / notExecuted / blocked 四種 |

詳細設計見 `docs/design/`；安全邊界見 [`sandbox-threat-model.md`](../design/sandbox-threat-model.md)。
