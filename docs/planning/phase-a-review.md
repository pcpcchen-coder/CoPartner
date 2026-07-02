# Phase A 檢視：可跑骨架 —「操作時間機器」

> 對象：backlog step 1–10（`docs/planning/implementation-backlog.md`）。
> 狀態：**step 1–9 程式碼完成、CI 全綠；step 10 為 🔒 真機 dogfood，待你在 Mac 上執行。**
> 日期：2026-07-02。

---

## 1. Phase A 交付了什麼

一句話：**把「輸入事件 → 去敏感的 human-readable 操作劇本 → 即時顯示在選單列」這條管線做出來，並包成一個真的能開起來的 macOS menu bar app。**

| # | 交付 | 型態 | 驗證 |
|---|---|---|---|
| 1 | CI 建置 app target（xcodegen + xcodebuild）| 基建 | ✅ CI |
| 2 | AttentionModel 回歸測試 + 時鐘注入 | 邏輯 | ✅ CI（8 測試）|
| 3 | EventTapMapper 事件映射 / InputEventTap 真 tap | 邏輯 + 🔒膠水 | ✅ CI（8 測試）+ 編譯 |
| 4 | FocusRegionResolver 焦點區 / SystemAXFocusProvider 真 AX | 邏輯 + 🔒膠水 | ✅ CI（8 測試）+ 編譯 |
| 5 | EventFormatter + L0Event 六種事件格式 | 邏輯 | ✅ CI（8 測試）|
| 6 | EventLog 合併/節流（打字續接、scroll 聚合）| 邏輯 | ✅ CI（9 測試）|
| 7 | PIIMasker PII 遮罩（TW/CN 身分證、手機、卡號）| 邏輯 | ✅ CI（10 測試）|
| 8 | EventLogFeed ring buffer + FocusChangeTracker + menu bar 顯示 | 邏輯 + 🔒膠水 | ✅ CI（8 測試）+ 編譯 |
| 9 | CaptureSessionState 狀態機 + KeyboardShortcuts 熱鍵/kill-switch | 邏輯 + 🔒膠水 | ✅ CI（7 測試）+ 編譯 |
| 10 | dogfood 驗收（操作時間機器）| 🔒 真機 | **待你執行**（見 §4）|

**新增測試合計：66 個**（連同既有 EscalationPolicy 5 + CoPartnerCore 1，全 repo 共 72 個），每次 push 由 macOS-15 runner 的 `swift test` 全綠把關；`app` job 另外保證 menu bar app 連同所有子系統實際建置得起來。

## 2. 架構原則落實狀況（自評）

**做得好的：**

- **純邏輯 / 平台膠水的乾淨切分，全程一致**：每個牽涉平台的東西（CGEventTap、AXUIElement、SCStream 之後、FoundationModels 之後）都抽成一層薄膠水 + protocol，把決策/計算邏輯獨立出來單元測試。即使我（開發代理）永遠在 Linux 上跑不了真機，專案的正確性核心仍有 66 個測試守著。
- **決定性測試**：時間相關邏輯（注意力衰減、打字合併窗、scroll 聚合、時間戳格式）一律用注入 `now:` / 固定 `TimeZone`，沒有一個測試依賴 wall-clock，不會 flaky。
- **安全關鍵路徑抽出來測**：PII 遮罩（漏遮＝個資外洩）與 kill-switch（接管工具最重要的停止鍵）都做成純值邏輯 + 測試，不埋在 UI 裡。
- **真的能跑**：不是一堆漂亮但沒接起來的函式庫——app target 進了 CI，menu bar app 把子系統接成一條會動的管線。

**誠實的技術債 / 限制（Phase A 期間發現，需後續處理）：**

1. **骨架目前只產生 FOCUS/SWITCH 事件**（app/視窗焦點時間軸），透過 NSWorkspace 應用切換 + AX 焦點讀取。**TYPE / PASTE / SCROLL 事件雖然 EventFormatter/EventLog/PIIMasker 都已完整支援且測試過，但還沒從真實輸入接起來**——因為從 InputEventTap 的 `Signal` 重建「打字的實際文字 / 貼上的剪貼簿內容」需要比目前 `Signal` 抽象更豐富的事件資料。也就是說：打字合併、貼上 PII 遮罩、scroll 聚合這些能力**存在且有單元測試，但骨架還沒端到端跑到它們**。這是明確要補的洞。
2. **「視窗」欄位是近似值**：目前用 `focusedElement()?.value`（焦點元件的 AX value）當視窗字串，不是真正的視窗標題（視窗的 `kAXTitleAttribute`）。FOCUS/SWITCH 行的 window 欄可能顯示元件內容而非視窗名。小事，之後修。
3. **AXObserver 尚未實作**：SystemAXFocusProvider 目前是 on-demand 讀取，反應式焦點通知留待後續（靠事件觸發時去讀就夠 Phase A 用）。
4. **InputEventTap 掛在主 run loop**：callback 假設在主執行緒，能動但不是型別層級強制。
5. **沒有端到端整合測試**：每層都有單元測試，但「輸入→翻譯→feed→UI」整條沒有整合測試（那部分是 🔒）。**step 10 的 dogfood 就是這條的整合驗證。**

## 3. 這對「最終成品」意味著什麼

Phase A 完成後，對照大目標（類 Siri×ChatGPT×Claude Desktop，開了就持續理解、下令就接手）：

- ✅ **「開啟後」** 有了：一個真的 menu bar app，開了就在記你的操作。
- 🟡 **「持續理解操作習慣」** 起步了：目前記的是 app/視窗焦點時間軸（＝一台好用的「你今天在哪些 app 之間切換」時間機器）；更細的打字/貼上內容與語意理解在 Phase B–E 疊上。
- ⏳ **「下令就接手」** 尚未開始：接手 HUD / 熱鍵交棒 / 雲端 computer-use 是 Phase F（step 43–49）。
- ✅ **「依難易度調用本地/雲端」** 的決策核心（ADR-0007 EscalationPolicy）在骨架前就已落地並測試。

## 4. Step 10 — 你的 dogfood 操作清單（🔒 需要你的 Mac）

我無法代跑（沒有 macOS / 螢幕 / 權限）。請在你的 Mac 上照做，並把結果回報給我，我依此修正 §2 的技術債並決定 Phase B 起點。

**前置**：macOS 15+、Xcode 16+、Homebrew。

```bash
# 1. 產生 Xcode 專案（會裝 xcodegen/uv）
./scripts/bootstrap.sh

# 2. 用 Xcode 開啟並執行（⌘R）
open apps/CoPartner/CoPartner.xcodeproj
#   選 CoPartner scheme → Run。這是 menu bar app（無 Dock 圖示），
#   請看選單列是否出現 eye.slash 圖示。
```

**操作與觀察：**

1. 點選單列圖示 → **「開始觀察」**（圖示應變 eye）。
2. 在 **Xcode ↔ Safari ↔ Finder** 之間切換幾次。
3. 看選單列面板的 **「操作劇本」** 是否即時出現 `[時間] SWITCH app=… ` / `FOCUS …` 行。
4. **測 kill-switch**：按 **⌃⌥⌘.** → 觀察應立即停止（圖示回 eye.slash、顯示「已停止觀察」）。
5. 按 **⌃⌥⌘O** → 應切回觀察。

**權限說明（重要）：**

- **app 切換追蹤（NSWorkspace）不需要任何 TCC 權限**，應該一開始就會記。
- 若要更細的焦點（AX）或輸入驅動：到「系統設定 → 隱私權與安全性」授予 **輸入監控** 與 **輔助使用** 給 CoPartner。
- ⚠️ 注意 `CONTRIBUTING.md` / `permissions-check.sh` 提到的陷阱：**未以 Developer ID 簽章的開發版 .app 在 macOS 26.1+ 可能不會乾淨地出現在權限清單**。若權限授不上去，**NSWorkspace 的 app 切換追蹤仍可運作**——骨架就是為此刻意設計成「免權限也有東西看」。

**驗收（roadmap M2.5「劇本完整重現一段操作」）：** 骨架版＝app/視窗焦點時間軸能忠實反映你的切換過程。

**請回報：** 劇本有沒有跑出來？熱鍵有沒有觸發？有沒有 crash？CPU（活動監視器）大概多少？這些會決定我下一步先補打字/貼上內容（§2 洞 1）還是直接進 Phase B 螢幕擷取。

## 5. 下一步

- **若 dogfood 順利**：進 **Phase B（step 11 起）** —— tile 幾何 / Metal dHash / SCStream dirtyRects，把螢幕視覺擷取疊到這台已經會跑的時間機器上。
- **若 dogfood 發現骨架內容太少不夠用**：先插一小段「輸入驅動的 L0 內容充實」（補 §2 洞 1 的 TYPE/PASTE/SCROLL 真接線）再進 Phase B。

依你 dogfood 的回報決定。
