import Foundation
// 設計：§B.5（多解析度金字塔）+ §B.6（能量帶）。純參數映射、CI 可測。
// 三層同時擷取：L0 焦點（高解析高頻小區）/ L1 周邊（中解析中頻大區）/ L2 概覽（降採樣全螢幕低頻心跳）。

/// 擷取金字塔的一層。
public struct CaptureLayer: Sendable, Equatable {
    public enum Region: Sendable, Equatable {
        case focus(radiusPt: Double)   // 以 attention center 為心
        case fullScreen                // 整個螢幕（降採樣）
    }
    public var region: Region
    public var scale: Double            // 解析度倍率（2.0 = retina 原生）
    public var fps: Double
    public var maxDimensionPt: Double?  // 長邊上限（L2 概覽 ≤ 1024）

    public init(region: Region, scale: Double, fps: Double, maxDimensionPt: Double? = nil) {
        self.region = region; self.scale = scale; self.fps = fps; self.maxDimensionPt = maxDimensionPt
    }

    /// fps == 0 代表該層此刻不擷取。
    public var isActive: Bool { fps > 0 }
}

/// 三層擷取金字塔（§B.5）。
public struct CapturePyramid: Sendable, Equatable {
    public var focus: CaptureLayer      // L0
    public var periphery: CaptureLayer  // L1
    public var overview: CaptureLayer   // L2

    public init(focus: CaptureLayer, periphery: CaptureLayer, overview: CaptureLayer) {
        self.focus = focus; self.periphery = periphery; self.overview = overview
    }

    /// L2 概覽長邊上限（§B.5）。
    public static let overviewMaxDimensionPt: Double = 1024

    /// 依注意力能量 A∈[0,1] 映射三層擷取參數（§B.5 / §B.6 四帶）。
    /// 能量越高：焦點區越大、解析度越高、FPS 越高；概覽層恆為低頻心跳（≤1024）。
    public static func forEnergy(_ energy: Double) -> CapturePyramid {
        switch energy {
        case 0.7...:      // HOT：點擊/拖曳後窗口
            return CapturePyramid(
                focus:     CaptureLayer(region: .focus(radiusPt: 400), scale: 2.0, fps: 8),
                periphery: CaptureLayer(region: .focus(radiusPt: 800), scale: 1.0, fps: 4),
                overview:  CaptureLayer(region: .fullScreen, scale: 0.5, fps: 1,
                                        maxDimensionPt: overviewMaxDimensionPt))
        case 0.4..<0.7:  // 升高：scroll / typing
            return CapturePyramid(
                focus:     CaptureLayer(region: .focus(radiusPt: 300), scale: 1.0, fps: 4),
                periphery: CaptureLayer(region: .focus(radiusPt: 600), scale: 0.5, fps: 2),
                overview:  CaptureLayer(region: .fullScreen, scale: 0.5, fps: 0.5,
                                        maxDimensionPt: overviewMaxDimensionPt))
        case 0.15..<0.4: // WARM：剛移動過
            return CapturePyramid(
                focus:     CaptureLayer(region: .focus(radiusPt: 250), scale: 1.0, fps: 2),
                periphery: CaptureLayer(region: .focus(radiusPt: 500), scale: 0.5, fps: 1),
                overview:  CaptureLayer(region: .fullScreen, scale: 0.5, fps: 0.5,
                                        maxDimensionPt: overviewMaxDimensionPt))
        default:         // COLD：焦點/周邊熄火，只剩概覽心跳
            return CapturePyramid(
                focus:     CaptureLayer(region: .focus(radiusPt: 0), scale: 0.5, fps: 0),
                periphery: CaptureLayer(region: .focus(radiusPt: 0), scale: 0.5, fps: 0),
                overview:  CaptureLayer(region: .fullScreen, scale: 0.5, fps: 0.2,
                                        maxDimensionPt: overviewMaxDimensionPt))
        }
    }
}
