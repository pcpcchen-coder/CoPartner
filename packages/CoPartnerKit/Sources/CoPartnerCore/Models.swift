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

// MARK: - 本地↔雲端分層推理路由（V2-E.1 / ADR-0007）

/// 推理階梯：本地優先，由便宜到貴。只有「大變動」才升到 `.cloud`。
public enum InferenceTier: Int, Sendable, Codable, Comparable {
    case localOCR = 0     // Vision dirty-tile 文字（§B.8）——最便宜
    case localIntent = 1  // FoundationModels 3B 意圖 / 路由（§D）
    case localVLM = 2      // Qwen2.5-VL 焦點拼接圖視覺語意（§D）
    case cloud = 3         // Claude computer-use（§E）——最貴，留給大變動 / 跨視窗任務
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// 驅動分層路由的訊號。由擷取 / 本地推理層產生，CloudRouter 的 `EscalationPolicy` 消費。
public struct RoutingSignal: Sendable {
    public var dirtyAreaRatio: Double   // 變動 tile 佔畫面比例 [0,1]（§B.2 dHash 聚合）= 「變動大小」
    public var attentionEnergy: Double  // 注意力能量 A∈[0,1]（ADR-0006）
    public var localConfidence: Double  // 本地模型對「已充分理解當前畫面」的信心 [0,1]
    public var contextSwitched: Bool    // 換 app / 視窗 / 版面（novelty）
    public var crossWindowTask: Bool    // 需跨視窗 / 多步規劃（單張焦點圖不足）
    public var containsSensitive: Bool  // 含敏感 / 上海個資 → 強制不出境（ADR-0005 / §G）
    public init(dirtyAreaRatio: Double = 0,
                attentionEnergy: Double = 0.5,
                localConfidence: Double = 1.0,
                contextSwitched: Bool = false,
                crossWindowTask: Bool = false,
                containsSensitive: Bool = false) {
        self.dirtyAreaRatio = dirtyAreaRatio
        self.attentionEnergy = attentionEnergy
        self.localConfidence = localConfidence
        self.contextSwitched = contextSwitched
        self.crossWindowTask = crossWindowTask
        self.containsSensitive = containsSensitive
    }
}

// MARK: - 雲端接手提議（V2-F / docs/design/sandbox-threat-model.md）

/// 雲端模型回傳的「提議動作」。**刻意結構化、無整串 shell 字串欄位**（不變式 I4）——
/// shell 類只有 argv，executor 以 posix_spawn 直帶 argv、不經 `sh -c`。風險分級由 step 50 判定。
public struct ProposedAction: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case screenshot
        case click(x: Int, y: Int)
        case typeText(String)
        case keypress(String)                              // 如 "cmd+s"
        case scroll(dx: Int, dy: Int)
        case shell(argv: [String])                         // 無整串命令字串（I4）
        case readFile(path: String)
        case writeFile(path: String, contents: String)
        case outboundComms(kind: String, target: String)   // 寄信 / 送出表單類（step 50 一律 high）
    }
    public let id: UUID
    public let kind: Kind
    public let rationale: String
    public init(id: UUID = UUID(), kind: Kind, rationale: String = "") {
        self.id = id
        self.kind = kind
        self.rationale = rationale
    }
}
