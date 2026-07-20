import Foundation
import CoPartnerCore
// 設計：docs/design/v2.1_action-script-narrator.md §2 L2（段落摘要：切 app session / 每數分鐘 rollup）。
// 規則式 rollup（CI 可測）；真 LLM 潤飾摘要可選 / 🔒。steps 需已按時間排序。

public struct L2Summary: Sendable, Equatable {
    public let startedAt: Date
    public let apps: [String]
    public let text: String
    public let stepCount: Int
    public init(startedAt: Date, apps: [String], text: String, stepCount: Int) {
        self.startedAt = startedAt
        self.apps = apps
        self.text = text
        self.stepCount = stepCount
    }
}

public enum L2Summarizer {
    /// 依 **app 切換 或 跨 window 時間窗**把 L1 steps 切段滾成摘要。
    public static func summarize(_ steps: [ActionStep], window: TimeInterval = 300) -> [L2Summary] {
        guard !steps.isEmpty else { return [] }
        var out: [L2Summary] = []
        var group: [ActionStep] = []

        func flush() {
            guard let first = group.first else { return }
            let apps = orderedUnique(group.map { $0.app })
            let goals = orderedUnique(group.map { $0.inferredGoal }.filter { !$0.isEmpty })
            var text = "在 \(apps.joined(separator: "、")) 進行 \(group.count) 個操作"
            if !goals.isEmpty { text += "；目標：" + goals.prefix(3).joined(separator: "、") }
            out.append(L2Summary(startedAt: first.startedAt, apps: apps, text: text, stepCount: group.count))
            group = []
        }

        for step in steps {
            if let last = group.last {
                let appChanged = step.app != last.app
                let tooFar = step.startedAt.timeIntervalSince(last.startedAt) > window
                if appChanged || tooFar { flush() }
            }
            group.append(step)
        }
        flush()
        return out
    }

    private static func orderedUnique(_ xs: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for x in xs where !seen.contains(x) {
            seen.insert(x)
            out.append(x)
        }
        return out
    }
}
