import Foundation
// 設計：v2.1 §3（熱劇本 RAM ring buffer）。把 L0 事件流變成即時可觀察的劇本快照。
// 可測邏輯（record / ring buffer / stop）由 CI 驗證；SwiftUI 顯示端在 app（🔒）。

/// 常駐的即時劇本 feed：吃 L0 事件、維持容量上限、對外提供「最新快照」串流。
public actor EventLogFeed {
    private var log: EventLog
    private var active = true
    private let continuation: AsyncStream<[String]>.Continuation

    /// 最新劇本快照串流（只保留最新一筆；訂閱端讀到的永遠是當下全部行）。
    public nonisolated let updates: AsyncStream<[String]>

    public init(capacity: Int = 500, timeZone: TimeZone = .current) {
        var l = EventLog()
        l.capacity = capacity
        l.timeZone = timeZone
        self.log = l
        let (stream, continuation) = AsyncStream<[String]>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.updates = stream
        self.continuation = continuation
    }

    /// 目前所有劇本行（快照）。
    public var lines: [String] { log.lines }

    /// 記錄一個 L0 事件並推播最新快照；停止後忽略。
    public func record(_ event: L0Event, at now: Date = Date()) {
        guard active else { return }
        log.record(event, at: now)
        continuation.yield(log.lines)
    }

    /// 停止：不再接收事件並結束串流。
    public func stop() {
        guard active else { return }
        active = false
        continuation.finish()
    }
}
