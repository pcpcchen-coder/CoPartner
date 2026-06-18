import Foundation
import CoPartnerCore
// 設計：docs/design/v2_smart-capture-engine.md §B
// TODO(M0): SCStream + SCStreamFrameInfo.dirtyRects 解析（§B.1）
// TODO(M0): Metal compute shader per-tile dHash（§B.2，shader 放 Resources/TileHash.metal）
// TODO(M0): CGEventTap 驅動 AttentionModel（§B.3）
// TODO(M1): tile 冷熱狀態機 + DYNAMIC 影片降頻（§B.6）
// TODO(M3): reference frame + delta 重建（§B.7）

public actor CaptureEngine {
    public init() {}
    public func start() async throws { /* TODO */ }
    public func stop() async { /* TODO */ }
}

/// 事件加權的注意力模型（ADR-0006 / §B.3.1）。
/// 注意力能量 A∈[0,1] 驅動 attention region 的大小、解析度與 FPS。
/// 點擊 = 動作起點 → 拉到峰值並立即強制高解析擷取；移動/靜置 → 隨時間衰減。
public actor AttentionModel {
    public enum Signal { case click, drag, scroll, keyDown, move(speed: Double), idle }

    private var energy: Double = 0          // A ∈ [0,1]
    private(set) var center: CGPoint = .zero
    private let halfLifeSeconds = 2.0
    private var lastUpdate = Date()

    public init() {}

    /// 收到輸入事件時更新能量（取 max，避免被低權重事件壓低）。
    /// 回傳 true 表示呼叫端應「立即強制一次高解析擷取」（點擊時）。
    @discardableResult
    public func update(_ signal: Signal, at point: CGPoint? = nil) -> Bool {
        decay()
        if let p = point { center = p }
        switch signal {
        case .click:           energy = 1.0; return true   // 動作起點：峰值 + 強制擷取
        case .drag:            energy = max(energy, 0.85)
        case .keyDown:         energy = max(energy, 0.8)    // 錨定 focused element（§B.4）
        case .scroll:          energy = max(energy, 0.6)
        case .move(let speed): energy = max(energy, 0.3 * (1 - min(max(speed, 0), 1))) // 快移→更低
        case .idle:            break                         // 只衰減
        }
        return false
    }

    private func decay() {
        let now = Date()
        let dt = now.timeIntervalSince(lastUpdate); lastUpdate = now
        guard dt > 0 else { return }
        energy *= pow(0.5, dt / halfLifeSeconds)
        if energy < 0.05 { energy = 0 }
    }

    /// 把能量映射成擷取參數（門檻分帶，對應 §B.6 狀態）。
    public func captureParams() -> (radiusPt: Double, scale: Double, fps: Double) {
        decay()
        switch energy {
        case 0.7...:     return (400, 2.0, 8)   // HOT：點擊/拖曳後窗口
        case 0.4..<0.7:  return (300, 1.0, 4)   // 升高：scroll / typing
        case 0.15..<0.4: return (250, 1.0, 2)   // WARM：剛移動過
        default:         return (0,   0.5, 0.2) // COLD：靜置 → 周邊心跳
        }
    }
}
