import Foundation
// 觀察 / 介入的會話狀態機（純值、可測）。AppCoordinator 以此為單一事實來源。
// kill-switch（stopAll）從任何狀態都回 idle 且冪等——「接手你電腦的工具」最重要的安全控制。

public struct CaptureSessionState: Sendable, Equatable {
    public enum Mode: String, Sendable { case idle, observing, intervening }
    public private(set) var mode: Mode = .idle
    public init() {}

    /// ⌃⌥⌘O：idle ↔ observing。
    public mutating func toggleObserve() { mode = (mode == .idle) ? .observing : .idle }
    /// 進入雲端介入（step 49 熱鍵觸發）。
    public mutating func beginIntervention() { mode = .intervening }
    /// 介入結束（完成 / 失敗 / 使用者 Stop）→ 回到觀察；非介入中則不動。
    public mutating func endIntervention() { if mode == .intervening { mode = .observing } }
    /// ⌃⌥⌘. 緊急停止：任何狀態 → idle，冪等。
    public mutating func stopAll() { mode = .idle }
}
