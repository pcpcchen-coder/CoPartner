import Foundation

// MARK: - 擷取引擎（V2-B）

/// 單一 tile 的變動事件（由 SCK dirtyRects + Metal dHash 產生）
public struct TileEvent: Sendable, Codable {
    public enum State: String, Sendable, Codable { case cold, warm, hot, dynamic }
    public let tileX: Int
    public let tileY: Int
    public let state: State
    public let dhash: UInt64
    public let timestamp: Date
    public init(tileX: Int, tileY: Int, state: State, dhash: UInt64, timestamp: Date) {
        self.tileX = tileX; self.tileY = tileY; self.state = state
        self.dhash = dhash; self.timestamp = timestamp
    }
}

// MARK: - 操作劇本（V2.1）

/// L1 敘事步驟。對應 FoundationModels 的 @Generable 結構（執行期版本在 ScriptNarrator）。
public struct ActionStep: Sendable, Codable, Identifiable {
    public let id: UUID
    public let startedAt: Date
    public let app: String
    public let category: String          // editing/reading/searching/debugging/...
    public let whatHappened: String
    public let inferredGoal: String
    public let confidence: Double
    public let artifacts: [String]
    public let openLoop: Bool
    public init(id: UUID = UUID(), startedAt: Date, app: String, category: String,
                whatHappened: String, inferredGoal: String, confidence: Double,
                artifacts: [String], openLoop: Bool) {
        self.id = id; self.startedAt = startedAt; self.app = app; self.category = category
        self.whatHappened = whatHappened; self.inferredGoal = inferredGoal
        self.confidence = confidence; self.artifacts = artifacts; self.openLoop = openLoop
    }
}

// MARK: - 雲端交棒（V2.1 §4）

public struct ActionScript: Sendable, Codable {
    public var sessionSummary: String     // L2
    public var recentSteps: [ActionStep]  // L1
    public var openLoop: String
    public init(sessionSummary: String, recentSteps: [ActionStep], openLoop: String) {
        self.sessionSummary = sessionSummary; self.recentSteps = recentSteps; self.openLoop = openLoop
    }
}

public struct TakeoverContract: Sendable, Codable {
    public enum Policy: String, Sendable, Codable { case suggestOnly, confirmEach, autoBounded }
    public var instruction: String
    public var policy: Policy
    public var allowedTools: [String]
    public init(instruction: String, policy: Policy, allowedTools: [String]) {
        self.instruction = instruction; self.policy = policy; self.allowedTools = allowedTools
    }
}

/// 熱鍵觸發時送往雲端的封包（V2-E.1 / V2.1 §4.1）
public struct ContextEnvelope: Sendable, Codable {
    public var triggerTimestamp: Date
    public var actionScript: ActionScript
    public var focusSnapshotJPEGBase64: String?
    public var focusedElementRole: String?
    public var focusedElementText: String?
    public var clipboardRecent: String?
    public var attentionSummary: String?
    public var takeover: TakeoverContract
    public init(triggerTimestamp: Date, actionScript: ActionScript,
                focusSnapshotJPEGBase64: String?, focusedElementRole: String?,
                focusedElementText: String?, clipboardRecent: String?,
                attentionSummary: String?, takeover: TakeoverContract) {
        self.triggerTimestamp = triggerTimestamp; self.actionScript = actionScript
        self.focusSnapshotJPEGBase64 = focusSnapshotJPEGBase64
        self.focusedElementRole = focusedElementRole; self.focusedElementText = focusedElementText
        self.clipboardRecent = clipboardRecent; self.attentionSummary = attentionSummary
        self.takeover = takeover
    }
}
