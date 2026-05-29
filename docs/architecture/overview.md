# 架構總覽

CoPartner 是混合式（本地 + 雲端）ambient AI 代理。三大支柱：

1. **Smart Capture Engine**（CaptureEngine）— foveated / dirty-region 螢幕擷取。
2. **Action Script Narrator**（ScriptNarrator）— 本地模型把操作寫成滾動劇本。
3. **Cloud Takeover**（CloudRouter）— 熱鍵觸發時把劇本交棒給 Claude 續寫。

```
感知 → 智慧擷取引擎 → 劇本敘事 → 記憶 ─┬─ 本地推理（意圖/視覺）
                                      └─ 熱鍵 → 雲端交棒（Claude Computer Use）→ 動作執行
                          橫切：隱私閘門（PII/黑名單/PIPL）、加密稽核、kill-switch
```

詳細設計見 `docs/design/`。模組對應 `packages/CoPartnerKit/Sources/`。
