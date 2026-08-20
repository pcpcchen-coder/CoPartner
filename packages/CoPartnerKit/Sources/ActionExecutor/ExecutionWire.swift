import Foundation
import CoPartnerCore
// 設計：sandbox-threat-model.md B4（沙箱執行）+ I4（無 shell 字串通道）+ T7（XPC 端驗簽）。
//
// 主 app 與 XPC service 之間的**線上格式**。純值 + Codable，因此整個編解碼契約
// 都能在 CI 驗；跨程序連線本身才是盲寫的膠水（🔒 真機）。
//
// ⚠️ 三件事刻意寫死在型別裡，不靠註解自律：
//
// 1. **沒有「整串命令」欄位**（I4）。shell 類動作只有 `argv: [String]`，
//    service 端因此連「拼回一個字串丟給 sh -c」的原料都拿不到。
//
// 2. **`ApprovalToken` 不過線**。這點違反直覺，但關鍵在於：**跨程序的值可以被偽造**。
//    誰能連上這個 endpoint，誰就能自己編一個 token 欄位；service 無從分辨。
//    所以授權留在偽造不了的地方——`ActionExecutor.execute` 在主 app 內驗 token（I1/I7），
//    service 端則驗**呼叫者是誰**（code-signing requirement，T7，第 ② 段）。
//    線上只帶 `actionID` / `generation` 當**稽核關聯用**（I9），不當授權憑證。
//
// 3. **UI 類動作（點按/輸入/捲動/截圖）不在這裡**。它們天生在使用者 session 權限內、
//    不經 shell 沙箱（威脅模型 R2），走的是主程序內的 AX/CGEvent 路徑。
//    把它們塞進沙箱線路只會製造「看起來被沙箱保護了」的假象。

/// 送往 XPC service 的一次執行請求。
public struct ExecutionRequest: Codable, Sendable, Equatable {
    /// 可走沙箱路徑的動作種類。**沒有** shell 字串、**沒有** UI 動作——理由見檔頭。
    public enum Kind: Codable, Sendable, Equatable {
        /// shell 類動作。**沙箱參數與 argv 綁在同一個 case 裡**，
        /// 因此「送了命令卻沒送沙箱設定」在型別上就組不出來——
        /// 那種組合的後果是「不知道該套哪個 profile」，而預設值在這裡沒有安全的選項。
        case shell(argv: [String], workspace: SandboxWorkspace)
        case readFile(path: String)
        case writeFile(path: String, contents: String)
        /// 除錯自檢：**不是一個動作**，service 只回報自己的身分資訊。
        ///
        /// 存在的理由是驗收：真的雲端傳輸接上之前，沒有任何辦法產生真提議，
        /// 也就沒有辦法驗證 XPC 這條線通不通。給它一個**專屬的 kind** 而不是
        /// 借用 `shell` 送個 `echo`，是為了讓「自檢入口」在第 ④ 段接上真執行之後
        /// 仍然不可能夾帶真動作——`selfTest` 永遠不是可執行的種類。
        case selfTest
    }

    /// 對應的 `ProposedAction.id`。**稽核關聯用，不是授權**（見檔頭第 2 點）。
    public let actionID: UUID
    /// handoff 世代號。同樣是稽核關聯用；真正的世代驗證在主 app 的 `ActionExecutor`（I7）。
    public let generation: Int
    public let kind: Kind

    public init(actionID: UUID, generation: Int, kind: Kind) {
        self.actionID = actionID
        self.generation = generation
        self.kind = kind
    }

    /// 自檢請求。actionID 每次新生，避免和真動作的稽核紀錄混淆。
    public static func selfTest() -> ExecutionRequest {
        ExecutionRequest(actionID: UUID(), generation: 0, kind: .selfTest)
    }
}

/// service 的回覆。
public enum ExecutionOutcome: Codable, Sendable, Equatable {
    /// 收到了，但**什麼都沒做**（第 ① 段 XPC 骨架的唯一正常結果）。
    ///
    /// 主 app 端必須把它當成「未執行」而 throw，不可當成成功——
    /// 骨架階段回報「已執行」會讓後面每一段驗收都失去意義。
    case acknowledgedNotExecuted(detail: String)
    /// service 拒收（無法解碼、種類不支援、呼叫者驗簽不過…）。
    case rejected(reason: String)
    /// 自檢回覆：證明 service 真的是**另一個程序**在跑。
    case diagnostics(SelfTestReport)
    /// 真的執行過了（第 53.5 段開啟後才可能出現）。
    case executed(ExecutionReport)
}

/// 一次真實執行的結果。
public struct ExecutionReport: Codable, Sendable, Equatable {
    /// 給人看的處置分類（succeeded / failed / timedOut …）。
    public let disposition: String
    /// **有沒有東西真的被執行**。稽核與 HUD 靠這個決定敢不敢說「已執行」——
    /// 不可從 `disposition` 的字串去猜，那是給人看的，不是給程式判斷的。
    public let didExecute: Bool
    public let stdout: String
    public let stderr: String

    public init(disposition: String, didExecute: Bool, stdout: String, stderr: String) {
        self.disposition = disposition
        self.didExecute = didExecute
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// 自檢報告。刻意包含 pid 與 euid：
/// 「XPC 有回應」不等於「跑在另一個程序」，也不等於「不是用你的權限在跑」，
/// 這兩件事都要看得到數字才算驗過。
public struct SelfTestReport: Codable, Sendable, Equatable {
    public let servicePID: Int32
    public let serviceEUID: UInt32
    public let serviceBundleID: String
    /// service 自述它目前**會不會執行任何東西**。第 ① 段固定為 false。
    public let willExecuteActions: Bool
    /// 呼叫者驗簽是否已啟用。
    public let verifiesCallerSignature: Bool
    /// 驗證狀態的一行說明（含實際使用的 requirement，或組不出來的原因）。
    /// 印出來是為了讓 bundle id / Team ID 打錯這種錯誤**看得見**——
    /// 否則只會表現成「連線莫名其妙被拒」。
    public let callerVerificationDetail: String

    public init(servicePID: Int32, serviceEUID: UInt32, serviceBundleID: String,
                willExecuteActions: Bool, verifiesCallerSignature: Bool,
                callerVerificationDetail: String) {
        self.servicePID = servicePID
        self.serviceEUID = serviceEUID
        self.serviceBundleID = serviceBundleID
        self.willExecuteActions = willExecuteActions
        self.verifiesCallerSignature = verifiesCallerSignature
        self.callerVerificationDetail = callerVerificationDetail
    }
}

/// 把提議轉成線上請求時可能的失敗。
public enum ExecutionWireError: Error, Equatable {
    /// UI 類動作不走沙箱路徑（威脅模型 R2）——它們該在主程序內以 AX/CGEvent 執行。
    case notSandboxable(String)
    /// shell 動作沒帶沙箱設定。**不給預設值**：預設的工作目錄與 exec 白名單
    /// 沒有一個安全的選項——太寬等於沒有沙箱，太窄等於靜默失敗。
    case missingWorkspace(String)
}

extension ExecutionRequest {
    /// 由已核准的提議組出線上請求。
    ///
    /// UI 類動作在這裡就**明確失敗**而不是被悄悄忽略：靜默忽略會讓 HUD 顯示「已執行」
    /// 而實際什麼都沒發生——那正是這個專案一路在避免的「假裝成功」。
    public static func from(action: ProposedAction, generation: Int,
                            workspace: SandboxWorkspace? = nil) throws -> ExecutionRequest {
        let kind: Kind
        switch action.kind {
        case let .shell(argv):
            guard let workspace else {
                throw ExecutionWireError.missingWorkspace(action.kind.summary)
            }
            kind = .shell(argv: argv, workspace: workspace)
        case let .readFile(path):
            kind = .readFile(path: path)
        case let .writeFile(path, contents):
            kind = .writeFile(path: path, contents: contents)
        case .screenshot, .click, .typeText, .keypress, .scroll, .outboundComms:
            throw ExecutionWireError.notSandboxable(action.kind.summary)
        }
        return ExecutionRequest(actionID: action.id, generation: generation, kind: kind)
    }
}

/// 線上編解碼。JSON 而非 NSSecureCoding：
/// 契約因此是純 Swift 值，CI 能完整驗證編解碼與相容性，跨程序部分只剩連線本身。
public enum ExecutionWire {
    public static func encode(_ request: ExecutionRequest) throws -> Data {
        try JSONEncoder().encode(request)
    }
    public static func decodeRequest(_ data: Data) throws -> ExecutionRequest {
        try JSONDecoder().decode(ExecutionRequest.self, from: data)
    }
    public static func encode(_ outcome: ExecutionOutcome) throws -> Data {
        try JSONEncoder().encode(outcome)
    }
    public static func decodeOutcome(_ data: Data) throws -> ExecutionOutcome {
        try JSONDecoder().decode(ExecutionOutcome.self, from: data)
    }
}
