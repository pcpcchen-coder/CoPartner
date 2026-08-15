import CoreGraphics
// 設計：§B.8「只 OCR 焦點/dirty 區」。決定「這次要把螢幕的哪一塊送去 OCR」。
// step 29 dogfood 發現：截整螢幕 OCR 會把選單列/其他 app 的字混進來（既不準又浪費），
// 且違反 M2 驗收指標（局部 OCR 吞吐 ≤ 全畫面的 ~20%）。純幾何、CI 可測。

public enum OCRCropPlanner {
    /// 由焦點框算實際裁切區：加 padding（焦點框常只框住輸入游標區，四周的標籤/內容也有用），
    /// 再夾進螢幕範圍。焦點框無效（.zero / 退化 / 完全在螢幕外）→ 回 nil 表示「這次略過」。
    public static func cropRect(focusFrame: CGRect?,
                                screenWidth: Int, screenHeight: Int,
                                padding: CGFloat = 40) -> CGRect? {
        guard screenWidth > 0, screenHeight > 0 else { return nil }
        guard let frame = focusFrame, frame.width > 1, frame.height > 1 else { return nil }
        let screen = CGRect(x: 0, y: 0, width: CGFloat(screenWidth), height: CGFloat(screenHeight))
        let padded = frame.insetBy(dx: -padding, dy: -padding)
        let clipped = padded.intersection(screen)
        guard !clipped.isNull, clipped.width > 1, clipped.height > 1 else { return nil }
        return clipped
    }

    /// 裁切區佔全螢幕的比例（吞吐指標：M2 目標 ≤ ~0.2）。無裁切區（略過）回 0。
    public static func areaRatio(cropRect: CGRect?, screenWidth: Int, screenHeight: Int) -> Double {
        guard let rect = cropRect, screenWidth > 0, screenHeight > 0 else { return 0 }
        let total = Double(screenWidth) * Double(screenHeight)
        guard total > 0 else { return 0 }
        return min(1, (Double(rect.width) * Double(rect.height)) / total)
    }
}
