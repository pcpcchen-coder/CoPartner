import Foundation
// 設計：sandbox-threat-model.md T8/I8。兩道：時間窗內動作數上限（rate）＋
// 同一動作連續重複偵測（loop）。任一觸發 → executor halt，須重新確認。注入 now 可測。

public struct RateLimiter: Sendable {
    public enum Verdict: Sendable, Equatable { case allow, rateLimited, loopDetected }

    private var timestamps: [Date] = []
    private var lastSignature: String?
    private var consecutiveSame = 0
    public let maxActionsPerWindow: Int
    public let window: TimeInterval
    public let loopThreshold: Int

    public init(maxActionsPerWindow: Int = 20, window: TimeInterval = 60, loopThreshold: Int = 3) {
        self.maxActionsPerWindow = max(1, maxActionsPerWindow)
        self.window = max(0.001, window)
        self.loopThreshold = max(1, loopThreshold)
    }

    /// 記錄一次動作（signature = 動作描述）。loop 判定優先於 rate。
    public mutating func record(_ signature: String, at now: Date) -> Verdict {
        if signature == lastSignature { consecutiveSame += 1 } else {
            lastSignature = signature
            consecutiveSame = 1
        }
        if consecutiveSame > loopThreshold { return .loopDetected }   // 連續第 threshold+1 次相同 → halt

        timestamps = timestamps.filter { now.timeIntervalSince($0) < window }
        if timestamps.count >= maxActionsPerWindow { return .rateLimited }
        timestamps.append(now)
        return .allow
    }
}
