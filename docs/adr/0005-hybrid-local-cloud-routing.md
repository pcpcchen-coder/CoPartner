# 5. 混合本地/雲端路由與隱私邊界

- 狀態：已接受
- 脈絡：使用者位於台灣、有上海團隊，受 PDPA 與 PIPL 跨境條款約束；部分資料絕不可出境。
- 決定：本地（FoundationModels 3B / Qwen MLX）負責持續觀察、意圖分類、PII 偵測；
  雲端（Claude）負責複雜推理與動作規劃；經 LiteLLM 路由 + Presidio 閘門；
  含上海團隊個資/敏感 tile 一律 local-only。
- 後果：需維護資料分類與 PII recognizer；雲端成本可控（prompt cache + 預算熔斷）。
