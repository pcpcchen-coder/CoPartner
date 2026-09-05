import AppKit
import ImageIO
import UniformTypeIdentifiers
import CoPartnerCore
import CaptureEngine
@preconcurrency import ScreenCaptureKit

// 🔒 真機膠水：擷取主顯示器 → 塗黑敏感區 → 縮到宣告尺寸 → JPEG → base64。
// CI 只保證編譯；判斷邏輯（尺寸、遮罩幾何、y 翻轉、出境決策）全在 CoPartnerKit 且有測試。
//
// ## 這個檔案的每一步都是「錯了不會報錯」的那種
//
// 1. **擷取錯的顯示器**：多螢幕時 `content.displays.first` 不一定是我們宣告幾何的那台。
//    抓錯螢幕 → 送出去的圖與宣告的尺寸對得上、內容卻是另一個畫面，模型看著 A 螢幕
//    給的座標會被套到 B 螢幕上。所以用 `NSScreen.main` 的 displayID **配對**，配不到就失敗。
// 2. **塗黑塗到鏡像位置**：見 `ScreenshotRedaction.bottomLeftPixelRects`。
// 3. **縮放與宣告不一致**：見 `ScreenshotScalePolicy`。
//
// 三者都不會丟例外，只會讓結果安靜地錯，所以每一步都寧可 throw 也不硬做。
enum ScreenshotEncoder {

    enum Failure: Error, CustomStringConvertible {
        case noScreen, displayMismatch, captureFailed(String), drawFailed, encodeFailed
        var description: String {
            switch self {
            case .noScreen: return "讀不到主顯示器"
            case .displayMismatch: return "配不到與宣告幾何相同的顯示器（多螢幕？）"
            case .captureFailed(let d): return "擷取失敗（\(d)）"
            case .drawFailed: return "建立不了繪圖 context"
            case .encodeFailed: return "JPEG 編碼失敗"
            }
        }
    }

    /// JPEG 品質。0.6 是取捨點：再高 base64 字元數（＝token）成長很快，
    /// 再低則小字開始糊掉，而模型讀不出小字就給不出正確座標。
    static let jpegQuality: CGFloat = 0.6

    struct Encoded {
        let base64: String
        let pixelSize: CGSize
        /// 實際塗黑了幾塊。**要回報出來**——「有遮罩機制」與「這一張真的遮了東西」
        /// 是兩件事，而前者在報告上看起來跟後者一樣。
        let redactedRegions: Int
        var byteCount: Int { base64.utf8.count }
    }

    /// 擷取 + 遮罩 + 編碼。
    ///
    /// - Parameters:
    ///   - targetSize: 送出去、同時也宣告給模型的尺寸（`ScreenshotScalePolicy`）。
    ///   - redact: **正規化**矩形（左上原點、y 向下），來自 `ScreenshotRedaction`。
    ///   - blacklist: 黑名單 app 在**擷取源頭**排除（step 56）——比事後塗黑更徹底，
    ///     那些視窗的像素根本不會進到這個程序裡。
    @MainActor
    static func capture(targetSize: CGSize,
                        redact: [CGRect],
                        blacklist: CaptureBlacklist) async throws -> Encoded {
        guard let screen = NSScreen.main,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? NSNumber else { throw Failure.noScreen }
        let wantedID = CGDirectDisplayID(number.uint32Value)

        let content: SCShareableContent
        do { content = try await SCShareableContent.current }
        catch { throw Failure.captureFailed("\(error)") }

        // ⚠️ 配對而不是拿第一台。多螢幕時 `displays.first` 不一定是我們宣告幾何的那台，
        //    而抓錯螢幕的後果是「尺寸對得上、內容是別的畫面」——完全不會報錯。
        guard let display = content.displays.first(where: { $0.displayID == wantedID }) else {
            throw Failure.displayMismatch
        }
        let excluded = content.applications.filter {
            blacklist.isBlocked(bundleID: $0.bundleIdentifier, appName: $0.applicationName)
        }
        let filter = SCContentFilter(display: display,
                                     excludingApplications: excluded, exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height

        let image: CGImage
        do { image = try await SCScreenshotManager.captureImage(contentFilter: filter,
                                                                configuration: config) }
        catch { throw Failure.captureFailed("\(error)") }

        let redacted = try redactAndScale(image, to: targetSize, normalizedRects: redact)
        return Encoded(base64: try encodeJPEGBase64(redacted),
                       pixelSize: targetSize,
                       redactedRegions: redact.count)
    }

    /// 縮放 + 塗黑。**一次繪製完成**——分兩次（先縮再塗、或先塗再縮）會多一次重採樣，
    /// 而重採樣後的黑塊邊緣會出現半透明的過渡像素，等於把遮罩邊緣的內容糊出來一點點。
    static func redactAndScale(_ image: CGImage, to size: CGSize,
                               normalizedRects: [CGRect]) throws -> CGImage {
        let width = Int(size.width.rounded()), height = Int(size.height.rounded())
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw Failure.drawFailed }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))

        // 不透明黑，且**不做任何混合**——半透明的遮罩等於沒遮。
        context.setBlendMode(.copy)
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        let rects = ScreenshotRedaction.bottomLeftPixelRects(normalizedRects,
                                                             targetSize: CGSize(width: width,
                                                                                height: height))
        if !rects.isEmpty { context.fill(rects) }

        guard let out = context.makeImage() else { throw Failure.drawFailed }
        return out
    }

    static func encodeJPEGBase64(_ image: CGImage) throws -> String {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil) else { throw Failure.encodeFailed }
        CGImageDestinationAddImage(destination, image,
                                   [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Failure.encodeFailed }
        return (data as Data).base64EncodedString()
    }
}
