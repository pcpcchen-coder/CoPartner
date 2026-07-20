import Foundation
import CoPartnerCore
// 設計：sandbox-threat-model.md T9。記錄反操作供 LIFO undo；**不可 undo 的動作＝barrier**——
// undo 到 barrier 停（不越過去回退更早的），這類動作在核准時已被 50/48 強制 high+confirm。
// 新 handoff 開新 scope。真反操作內容（檔案快照 / AX 前狀態 / git stash）🔒 由執行時填。

public struct UndoStack: Sendable {
    public enum Entry: Sendable, Equatable {
        case restorable(id: UUID, inverse: ProposedAction)   // 可回退：存反操作
        case barrier(id: UUID, label: String)                // 不可回退（寄信/付款類）：undo 止步於此
    }

    private var entries: [Entry] = []
    public init() {}

    /// 新 handoff：清掉上一輪的 undo 範圍。
    public mutating func beginScope() { entries.removeAll() }

    public mutating func push(_ entry: Entry) { entries.append(entry) }

    /// 頂端可回退 → 彈出並回傳反操作；頂端是 barrier 或空 → nil（止步）。
    public mutating func popUndo() -> ProposedAction? {
        guard case let .restorable(_, inverse) = entries.last else { return nil }
        entries.removeLast()
        return inverse
    }

    public var canUndo: Bool {
        if case .restorable = entries.last { return true }
        return false
    }

    public var count: Int { entries.count }
}
