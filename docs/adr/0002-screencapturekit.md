# 2. 採用 ScreenCaptureKit 而非 CGDisplayStream

- 狀態：已接受
- 脈絡：CGDisplayStream（含其 dirtyRects）於 macOS 14+ 已 deprecated。
- 決定：螢幕擷取一律使用 ScreenCaptureKit（macOS 12.3+），讀取 SCStreamFrameInfo.dirtyRects。
- 後果：依賴 SCK 的 dirty rects 可靠性；以 Metal dHash 作為 ground-truth 驗證（見 ADR-0003）。
