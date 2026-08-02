# Step 18 — M0 真機驗收：螢幕擷取 dogfood 清單（🔒 需要你的 Mac）

> 目標：確認 Phase B 的螢幕擷取整條在真硬體上運作——SCStream 抓幀、Metal 算 per-tile hash、
> dirty 融合、冷熱狀態機、選單即時反映。這是「螢幕視覺」層第一次在真機驗證。
> 我（開發代理）無法代跑（Linux 容器、無 Mac/GPU/螢幕/權限）。CI 只保證編譯，行為要你驗。
> 日期：2026-07-19。

---

## 0. 先更新（有新檔 → 一定要重跑 bootstrap）

```bash
cd ~/Documents/CoPartner       # 你的 repo 路徑
git pull origin claude/loving-darwin-Ka636
./scripts/bootstrap.sh          # ← 這次新增了 SCKFrameProducer.swift 等檔案，必須重新產生專案
open apps/CoPartner/CoPartner.xcodeproj
```

Xcode 若已開著會提示專案檔變更 → 讓它重新載入（或關掉重開）。⌘R 執行。

## 1. 授權（這次多一個 Screen Recording）

到「系統設定 → 隱私權與安全性」，確認 CoPartner 有：
- **螢幕錄製（Screen Recording）** ← **這步新增，擷取一定要它**
- 輸入監控（Input Monitoring）— 打字/捲動事件
- 輔助使用（Accessibility）— 焦點

⚠️ 授權後**回 Xcode 停止(■)再重跑(⌘R)**（權限對新程序才生效）。
⚠️ 未簽章的開發版在 macOS 26.1+ 有時 TCC 會怪怪的（見 `CONTRIBUTING.md`）；若螢幕錄製授不上或授了沒反應，把 CoPartner 從清單移除再重加、或重開機一次。

## 2. 觀察

1. 選單列點 CoPartner → 「開始觀察」。
2. 看面板頂端的 **「螢幕擷取：…」** 那一行：
   - 剛開：`啟動中…`
   - 正常運作：應變成 **`螢幕擷取：N 次變動，最新 tile (x,y)`**，且隨你動視窗/打字**即時跳動**。
   - 若顯示 `未啟用（…）`：把後面的錯誤訊息回報給我（多半是權限或 Metal 問題）。
3. 移動視窗、捲動、打字 → 擷取摘要的「N 次變動」應快速增加。
4. **播一段影片**（YouTube/QuickTime）→ 影片區的 tile 應被判為 DYNAMIC（目前 UI 只顯示變動計數，DYNAMIC 狀態在事件流裡；先確認「播影片時 CPU 沒爆、變動計數飆高但程式順」）。
5. 測 kill-switch（你設的熱鍵，或選單「緊急停止」）→ 擷取應停止、摘要回「未啟用」。

## 3. 量測（step 17 的數字）

開「活動監視器」搜 **CoPartner**，記錄：
- **CPU %**（觀察中、桌面靜置時）——目標感覺：靜置應很低（個位數），操作時上升但不燙。
- **CPU %**（播 1080p 影片時）——DYNAMIC 降頻的意義就在這；若這時 CPU 飆到很高，代表 DYNAMIC 跳過 OCR/降頻的效益要在後續 milestone 補（目前只到「標記 DYNAMIC」，真正降頻擷取是之後）。
- **記憶體**、風扇/溫度體感。

## 4. 請回報這幾點

1. 「螢幕擷取：…」那行**有沒有動**？數字有沒有隨操作增加？（＝ SCStream+Metal+管線整條通了沒）
2. 有沒有顯示 `未啟用（錯誤）`？錯誤訊息是什麼？
3. 靜置 / 操作 / 播影片 三種情況的 **CPU %** 大概各多少？
4. 有沒有 crash、卡頓、風扇狂轉？
5. 事件日誌（操作劇本）跟之前一樣正常嗎？（擷取不該弄壞它）

## 5. 已知待確認（真機才知道，回報後我修）

- **Retina 縮放**：我用 `display.width/height`（點）同時當擷取尺寸與 tile grid 尺寸——兩者一致所以邏輯自洽，但可能是 1x 而非原生 2x。若你覺得「變動偵測解析度不夠細」，這裡要改成 ×backingScaleFactor。
- **dirtyRects 座標慣例 / contentRect X=48**：resolver 刻意不信 contentRect.origin、以 hash 為準；若發現「明明改了畫面卻沒偵測到變動」或「整片誤報」，回報，我調融合邏輯。
- **per-app override 尚未接**：producer 目前 `app: nil`，所以股價 ticker 之類還不會被排除（step 21 邏輯已測，只差把前景 app 名餵進來）。
- **CPU 若偏高**：最可能是「每幀都 hash 整個螢幕的所有 tile」——之後 M1 的 tile 狀態機降頻 + 只 hash dirtyRects 命中的 tile 可優化（目前求對不求快）。

驗完把 §4 回報給我，我據此：(a) 修真機發現的問題、(b) 標記 step 18 完成、(c) 決定接著補 §5 的優化還是進 Phase C（OCR）。
