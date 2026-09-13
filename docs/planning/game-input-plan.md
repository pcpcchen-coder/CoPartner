# GameInput 實作計畫：模擬鍵盤滑鼠操作 Roblox

> 範圍與四條硬約束見 [`../adr/0009-game-input-module-scope.md`](../adr/0009-game-input-module-scope.md)。
> 本文是**怎麼做**：型別設計、驗證階梯、分步 DoD。

**本輪範圍：底層輸入模擬層。** 不含錄製重播、不含巨集腳本、不含 AI 決策——
那些是這層之上的東西，而這層沒做對，上面全是空談。

**目標環境：正式 Roblox 遊戲**（無自建 Studio 靶場，使用者決定）。
這個選擇的代價寫在 §1 與 §6，整份計畫的形狀主要由它決定。

---

## 0. 為什麼不能直接用現有的 `UIActionPerformer`

`apps/CoPartner/Sources/UIActionPerformer.swift` 已經真機驗過（2026-09-03），
會送 CGEvent、走 `.cghidEventTap`、座標換算有防呆。拿它打 Roblox 會失敗，
而且是**五種不同的失敗**，每一種都必須各自解：

| # | 缺口 | 具體後果 |
|---|---|---|
| 1 | **沒有「按住」** | `press()` 是 down+up 連發。`ProposedAction.Kind` 型別上就組不出「按住 W 一點二秒」——角色只會抽動一下 |
| 2 | **沒有相對位移** | Roblox 轉視角時把游標與滑鼠解除關聯（`CGAssociateMouseAndMouseCursorPosition(false)`），此時**絕對座標完全無效**，必須填 `.mouseEventDeltaX/Y` |
| 3 | **座標系不對** | `ScreenCoordinateMapper` 算的是「模型截圖像素 → 全域點」。遊戲要的是「Roblox 視窗內 → 全域點」，缺視窗幾何來源 |
| 4 | **驗證手段失效** | `dryRun` 靠 AX 報「那個位置上是什麼」。ADR-0008 §1 親口寫下遊戲在 AX 上是不透明節點——對 Roblox 這行永遠回「讀不到」 |
| 5 | **閘門方向相反** | 現有設計是每個動作 HUD 人工確認。遊戲是連續高頻輸入，逐一確認不可行；但「不確認」不能等於「沒有煞車」（見 §3.6） |

第 1、2 項是**型別層的缺**，不是參數調不對——所以 `GameInput` 從新的型別開始，
不是在舊型別上加旗標。

---

## 1. 驗證階梯：沒有 ground truth 時，能做到的最好的事

這是整份計畫的支點，所以放在型別設計之前。

正式遊戲是黑盒：**送出事件之後，遊戲沒反應，我們看不到任何理由。**
可能是事件根本沒進系統、可能是格式錯、可能是進了系統但 Roblox 忽略合成事件、
可能是視窗沒前景、可能是座標落在別的地方。這五種在畫面上長得一模一樣——
而這正是本專案從第一天就在防的東西：**做不到的時候要大聲說做不到。**

不能取得證明，就退而求其次：**把單一的「沒反應」切成幾種可區分的失敗。**
三層，每層各自可獨立通過或失敗，失敗的那一層直接指出病灶：

### L1 — 自我迴讀（不需要任何外部 app）

裝一個 **listen-only** 的 `CGEventTap`，讀自己剛送出去的事件。

關鍵在於分得出「自己送的」與「真人手按的」：
`CGEventSource.userData` 設一個 magic 值，送出的每個事件都帶著它，
tap 端用 `event.getIntegerValueField(.eventSourceUserData)` 讀回比對。
沒有這個標記，自我迴讀在你手放鍵盤上的那一刻就開始說謊。

- **通過** = 事件確實進入了系統事件流。
- **失敗** = 權限問題（輔助使用／輸入監控）、secure input 開著、或事件根本沒建成功。
- **證不了**：任何 app 有沒有收到。L1 只管「送出去了沒」。

### L2 — 中性靶（一個 30 行的 SwiftUI 視窗）

`scripts/input-target/`：一個最小視窗，把收到的每個 `NSEvent`
（keyDown／keyUp／flagsChanged／mouseMoved 的 deltaX/Y／scrollWheel）印在畫面上。

**這不是 Roblox，刻意不是。** 它的用途是把「我們的事件格式對不對」
跟「Roblox 有沒有特別處理」拆成兩個問題。

- **通過** = 事件格式正確，一般 macOS app 收得到，`deltaX/Y` 有值。
- **L1 過但 L2 掛** = 事件進了系統但送不到前景 app——前景化或 tap 位置錯。
- **證不了**：Roblox 收不收。

### L3 — Roblox 黑盒（三個遞增的探針）

沒有 Lua 可以印，但 Roblox 客戶端本身會對某些輸入產生**肉眼可見且不可能誤判**的反應。
三個探針，由易到難，每一個各自驗一項能力：

| 探針 | 做法 | 驗的是 | 掛掉代表 |
|---|---|---|---|
| **A. 聊天框打字** | 按 `/` 開聊天 → 送一串字 → 字出現在輸入框 | 鍵盤事件進得去 Roblox | 合成鍵盤事件被整個忽略 → §6 fallback 階梯 |
| **B. WASD 前進** | 按住 `W` 一點五秒 → 畫面應大幅改變 | **按住**（§2.1）真的成立 | down/up 配對或持續時間有問題（A 過才有意義） |
| **C. 右鍵拖曳轉視角** | rightMouseDown → 連續 delta → rightMouseUp | **相對位移**（§2.1）真的成立 | delta 欄位沒被讀到 → 試 `.rightMouseDragged` 而非 `.mouseMoved` |

B 與 C 的「畫面有沒有變」不靠肉眼：用 repo 既有的 `CaptureEngine` tile hashing
取動作前後兩張，比對變動 tile 佔比。這是**唯一**能把黑盒反應變成可打勾數字的方法，
而且它剛好是這個 repo 已經有的東西。

> ⚠️ **誠實說明**：L3 全過只證明「Roblox 對我們的事件有反應」，
> 不證明「反應正確」。沒有靶場就沒有這個東西。這是 §6 記下的已知限制。

---

## 2. 純值層（CI 可測，`swift test` 就跑得到）

照本專案的鐵律切：**判斷邏輯全在純值型別裡，膠水層只負責把驗過的東西送出去。**

### 2.1 `InputPlan` / `InputStep` — 時間軸型別

核心認知：**遊戲輸入是時間軸上的狀態，不是離散命令。** 型別要逼人寫出時間。

```
enum InputStep {
    case keyDown(GameKey)
    case keyUp(GameKey)
    case mouseDown(MouseButton)
    case mouseUp(MouseButton)
    case moveAbsolute(WindowPoint)      // 視窗內座標
    case moveRelative(dx: Int, dy: Int) // 視角用
    case scroll(dx: Int, dy: Int)
    case wait(Duration)
}
```

**`moveAbsolute` 與 `moveRelative` 是兩個 case，不是一個帶旗標的 case。**
理由與 `ExecutionWire.Kind.dryRun` 選擇專屬 kind 完全相同：旗標會有預設值，
而預設錯的方向是「以為在送 delta、其實送了絕對座標」——後果是**視角完全不動，
而且不會報錯**。專屬 case 沒有這個問題。

`hold(key:duration:)` 不是第九個 case，是一個展開成 `keyDown → wait → keyUp`
的建構器——讓「按住」在型別上永遠是配對好的，見 §2.2。

### 2.2 `KeyHoldLedger` — 按住帳本（這一層的頭號安全裝置）

**遊戲輸入最危險的失敗不是送不出去，是送了 `keyDown` 沒送 `keyUp`。**

後果超出程式本身：那個鍵在**整個系統**都還按著。角色一直往前跑進岩漿是小事，
卡住的若是 `shift` 或 `cmd`，你接下來每一次按鍵都變成別的意思，
而且關掉 CoPartner 也救不回來——沒有人會聯想到是這裡。

帳本記錄每個還沒配對的 `keyDown`，提供 `releaseAll()`。

**可在 CI 驗的不變式**：任何 `InputPlan` 靜態展開後，帳本必須歸零。
不平衡的 plan **在建構時就被拒絕**，不是等到執行時才發現。

真機端三道保險（§3）：`defer` 釋放、程序終止 hook、看門狗逾時。

### 2.3 `GameCoordinateMapper` — 視窗內 → 全域

與 `ScreenCoordinateMapper` 同一種寫法（**先化成比例再乘回去**，
不出現 `backingScale`，理由見該檔註解），但輸入是 Roblox 視窗矩形而非顯示器。

越界**拒絕，不夾邊**——照舊：夾邊會把「算錯座標」變成「點在視窗邊緣」，
一個看起來成功的動作。

### 2.4 `GameKeyMap` — 鍵名 → 虛擬鍵碼

`ActionExecutor/VirtualKeyMap.swift` 的**刻意複製**（ADR-0009 硬約束 1）。
同樣用 Carbon 具名常數，同樣認不得就回 `nil`。

差別：遊戲走的是**位置鍵碼**（WASD 是鍵盤上的位置），
所以這裡**沒有** `typeText` 那條 `keyboardSetUnicodeString` 的路徑——
除了 L3 探針 A 的聊天框打字，那是唯一需要真打字的地方，單獨一個 API。

### 2.5 `InputPacing` — 時序

**理由不是反偵測，是 frame timing。** Roblox 每 frame 輪詢輸入；60fps 是 16.7ms。
一個 down 與 up 間隔 0ms 的按鍵可能整個落在同一次輪詢之間，
遊戲**完全看不到**——而 `CGEvent.post` 兩次都會回報成功。

- 最小按鍵持續時間 **50ms**（≈3 frames @60fps）。
- 連續 delta 事件切成小步送（一次 -340px 的視角轉動要分成多個事件），
  否則遊戲可能把它夾住或整個丟掉。

可測：給定 plan → 產生時間戳序列 → 斷言最小間隔與總時長。

### 2.6 `SafetyPolicy` — 煞車（取代逐一確認）

§0 第 5 點的解法。不是「不確認」，是把確認換成**可在 CI 驗的上界**：

- 單一 plan 總時長上限；
- 單鍵最長按住時間上限（超過必定是忘了 `keyUp`）；
- 每秒事件數上限；
- 巨集不得包含 `cmd` 修飾鍵（`⌘Q`／`⌘W` 在遊戲裡沒有用途，出現一定是搞錯了，
  而後果是關掉遊戲或登出）。

違反 → **建構時拒絕**，不是執行時中止。

---

## 3. 真機膠水層（🔒 CI 只保證編譯）

### 3.1 `GameEventPoster`

- `keyDown` / `keyUp` **分離**（現有沒有）。
- **相對位移**：建 `.mouseMoved`（或拖曳時 `.rightMouseDragged`）事件後
  `setIntegerValueField(.mouseEventDeltaX/.mouseEventDeltaY)`。
  游標鎖定時 `mouseCursorPosition` 無意義但仍需給值——用目前游標位置。
- `.cghidEventTap`（現有已選對，最接近硬體層）。
- `CGEventSource.userData` 打 magic 值，供 L1 自我迴讀比對。
- **送出前檢查 `IsSecureEventInputEnabled()`**：有 app 開著 secure input 時
  所有合成鍵盤事件被靜默吃掉。不檢查的話，這會表現成「Roblox 不吃我們的事件」，
  然後往 §6 的 fallback 階梯白走一趟。

### 3.2 `RobloxWindowLocator`

- `CGWindowListCopyWindowInfo` 取 Roblox 視窗矩形。
- **前景化**：`NSRunningApplication.activate()`。沒有前景，鍵盤事件送給別的 app——
  這是最容易發生、最容易誤判成「遊戲不理我」的一種失敗。
- ⚠️ **bundle identifier 待真機確認**，不寫死猜測值。找不到視窗時明確報
  「找不到 Roblox 視窗」，**不可以退回主顯示器全螢幕**——那會讓所有座標安靜地錯掉。

### 3.3 `SelfEchoVerifier`

L1 的實作。`CGEvent.tapCreate` listen-only，比對 magic 值，
回報「送出 N 個、迴讀 M 個」。N ≠ M 本身就是診斷。

### 3.4 緊急停止

四道，缺一不可（理由見 §2.2）：

1. `defer { ledger.releaseAll() }` 包住每次執行；
2. 全域熱鍵中止（app target 已相依 `KeyboardShortcuts`）；
3. 程序終止 hook（`NSApplication` 終止 + `SIGINT`／`SIGTERM`）；
4. **看門狗**：超過 `SafetyPolicy` 總時長上限自動 `releaseAll()`。

### 3.5 診斷報告寫檔案，不塞選單

本專案在「報告塞進選單被截斷」上已經栽過三次（見 `UIActionPerformer.verdict` 註解，
被截掉的正好是最該看的 `⌘Q` 鍵碼那兩行）。GameInput 的乾跑與三層驗證報告
一律寫 `Diagnostics/game-input-*.txt`。

---

## 4. 分步

每步一個 PR。**能力旗標單獨翻開**，照 step 53.5／53.6-C 的慣例——
翻開執行能力若混在一大包程式碼裡，沒有人能真的審完。

| 步 | 內容 | DoD |
|---|---|---|
| **G1** | 純值層全部（§2.1–2.6）＋ 新 target。`willPostGameEvents = false` | ✅ CI：帳本歸零不變式、plan 時序、座標換算越界拒絕、SafetyPolicy 拒絕條件、鍵碼表 |
| **G2** | `GameEventPoster` ＋ `SelfEchoVerifier` ＋ `RobloxWindowLocator`。**旗標仍 false**，只跑乾跑與 L1 | ✅ CI 編譯 ＋ 🔒 真機：L1 自我迴讀 N=M、secure input 檢查有輸出、Roblox 視窗矩形讀得到 |
| **G3** | L2 中性靶（`scripts/input-target/`） | 🔒 真機：按住 W 在靶上顯示 keyDown 後 1.5 秒才 keyUp；delta 欄位有值 |
| **G4** | **翻開 `willPostGameEvents = true`** | 單獨 PR，不夾帶其他改動。回滾方式：翻回 false |
| **G5** | L3 三個探針（A 聊天框／B WASD／C 視角） | 🔒 真機：A 字出現；B、C 用 tile hash 變動佔比 |
| **G6** | 緊急停止真機驗證 | 🔒 真機：執行中強制 kill，確認**沒有任何鍵卡住**（這一項必須主動製造失敗來驗，不能只看正常路徑通過） |

**G2 的順序是刻意的**：ADR-0009 把「`.cghidEventTap` 進不進得去遊戲」列為核心未知，
所以它排在第一個被證偽的位置，不是最後才發現。G1–G4 做完卻在 G5 全掛，
損失是四個 PR；反過來先寫好上層再發現底層不通，損失是整個專案。

---

## 5. 檔案

```
packages/CoPartnerKit/Sources/GameInput/     新 target，不相依 ActionExecutor
├── InputPlan.swift          §2.1
├── KeyHoldLedger.swift      §2.2
├── GameCoordinateMapper.swift §2.3
├── GameKeyMap.swift         §2.4（VirtualKeyMap 的刻意複製）
├── InputPacing.swift        §2.5
└── SafetyPolicy.swift       §2.6

apps/CoPartner/Sources/GameInput/            🔒 真機膠水
├── GameEventPoster.swift    §3.1
├── RobloxWindowLocator.swift §3.2
└── SelfEchoVerifier.swift   §3.3

scripts/input-target/                        §1 L2 中性靶
```

---

## 6. 已知限制與風險（誠實說明）

1. **Roblox 使用條款禁止 bot／macro／automation，帳號可能被停權。**
   技術上解不掉，記在這裡讓之後讀到的人不必重新發現。

2. **沒有靶場 → L3 是推論不是證明。** 三層階梯能區分失敗原因，
   但「Roblox 對事件有反應」不等於「反應正確」。

3. **核心未知：合成事件可能被遊戲整個忽略。** 若 L1、L2 全過而 L3 探針 A 掛掉，
   就是撞到這個。fallback 階梯（依成本排序，逐項試）：

   | # | 嘗試 | 成本 |
   |---|---|---|
   | 1 | 打開 `.keyboardEventAutorepeat` 旗標——有些引擎靠 repeat 判斷持續按住 | 低 |
   | 2 | `.cghidEventTap` ↔ `.cgSessionEventTap` 對調試 | 低 |
   | 3 | `CGEventSource` stateID 由 `.combinedSessionState` 改 `.hidSystemState`（現有註解說前者是為了修飾鍵，遊戲可能相反） | 低 |
   | 4 | `CGWarpMouseCursorPosition` ＋ `CGAssociateMouseAndMouseCursorPosition` 配合處理游標鎖定 | 中 |
   | 5 | DriverKit 虛擬 HID driver | **高一個數量級**，需要 entitlement，要單獨評估是否值得 |

   1–4 全掛就代表 Roblox 走的是 IOHID raw input，那時候要回頭問的是
   「這件事值不值得做到第 5 項」，不是繼續試。

4. **多螢幕**：`UIActionPerformer.dryRun` 已記錄這是會靜默出錯的已知風險。
   GameInput 以 Roblox 視窗矩形為準，不以顯示器為準，因此不受影響——
   但前提是 §3.2 找不到視窗時**拒絕**而非退回預設值。

5. **鍵盤佈局**：位置鍵碼是 ANSI 佈局。非美式佈局下 WASD 的**位置**仍然正確
   （遊戲讀的就是位置），所以這一層不受影響——但探針 A 的聊天框打字會受影響，
   那條路徑走 Unicode string，與佈局無關。
