import Foundation
// 設計：§L（風險緩解——per-app 排除 DYNAMIC 判定）。
// 有些 app 合法地一直變（股價 ticker、時鐘），但不是影片；使用者可標記其不套 DYNAMIC。純值、CI 可測。

public struct CaptureOverrides: Sendable, Equatable {
    private var neverDynamicApps: Set<String>

    public init(neverDynamicApps: Set<String> = []) {
        self.neverDynamicApps = neverDynamicApps
    }

    /// 標記 / 取消某 app「永不判為 DYNAMIC」。
    public mutating func setNeverDynamic(_ app: String, _ enabled: Bool = true) {
        if enabled { neverDynamicApps.insert(app) } else { neverDynamicApps.remove(app) }
    }

    /// 該 app 是否允許 DYNAMIC 判定。
    public func allowsDynamic(app: String) -> Bool {
        !neverDynamicApps.contains(app)
    }

    /// 目前被排除的 app（排序，供設定 UI）。
    public var neverDynamicList: [String] { neverDynamicApps.sorted() }
}
