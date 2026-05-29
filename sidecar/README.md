# CoPartner Sidecar

Python 本地推理 sidecar，跑在 `127.0.0.1:8765`，僅供本機 Swift 主程序呼叫。

```bash
uv sync
uv run copartner-sidecar
```

只承擔視覺重活（Qwen2.5-VL via MLX）與 OCR fallback。意圖分類與 L1 劇本敘事由 Swift 端的
Apple FoundationModels 處理（見 packages/CoPartnerKit/Sources/ScriptNarrator）。
