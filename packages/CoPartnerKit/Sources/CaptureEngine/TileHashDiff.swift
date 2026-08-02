import Foundation
// 設計：docs/design/v2_smart-capture-engine.md §B.2（Metal per-tile dHash 驗證 dirty）
// 純比對邏輯（CI 可測）。hash 的「產生」在 GPU（TileHash.metal + TileHashComputer，🔒）；
// 這裡只負責「兩個 hash 差多少、算不算真的變了」——讓分級門檻可離線調校與回歸。

/// 單一 tile 兩幀之間的變動幅度分級。
/// M1 的 tile 狀態機（step 19）與 DirtyRegionResolver（step 13）都吃這個分級。
public enum ChangeMagnitude: Sendable, Equatable {
    case none    // hash 相同：像素未變
    case small   // 少量 bit 翻轉：游標殘影 / 反鋸齒級雜訊，不值得喚醒下游
    case large   // 多 bit 翻轉：內容真的變了
}

/// 分級門檻。預設為保守起點，於 M0 真機驗收（step 18）以實測資料調校。
public struct ChangeThresholds: Sendable, Equatable {
    /// Hamming distance ≤ 此值（且 >0）視為 `.small`。
    /// 直覺：128px tile 的 dHash 是 9×8 亮度格的 64 個相鄰比較位；
    /// 游標（~20px）只掃過 1–4 個格，翻 1–2 bit；真的內容變動動輒 4bit 以上。
    /// 設 0 可停用 small 分級（任何變動都算 large）。
    public var smallMaxBits: Int
    public init(smallMaxBits: Int = 2) { self.smallMaxBits = max(0, smallMaxBits) }
}

public enum TileHashDiff {
    /// 兩個 64-bit dHash 的 Hamming distance（翻轉的 bit 數，0…64）。
    public static func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }

    /// 依 distance 分級。
    public static func classify(distance: Int, thresholds: ChangeThresholds = ChangeThresholds()) -> ChangeMagnitude {
        if distance <= 0 { return .none }
        return distance <= thresholds.smallMaxBits ? .small : .large
    }

    /// 便利：直接比兩個 hash。
    public static func classify(old: UInt64, new: UInt64,
                                thresholds: ChangeThresholds = ChangeThresholds()) -> ChangeMagnitude {
        classify(distance: hammingDistance(old, new), thresholds: thresholds)
    }
}
