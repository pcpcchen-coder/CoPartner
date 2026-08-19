import Foundation
import ActionExecutor

// XPC service 進入點（🔒 真機膠水）。
//
// `NSXPCListener.service()` 會阻塞並接管這個程序的生命週期——
// 由 launchd 依需求啟動、閒置時回收，主 app 不需要自己管 spawn 與收屍。
//
// ⚠️ **不要在 service listener 上呼叫 `setConnectionCodeSigningRequirement`。**
// 真機實測（step 53.2）：service 一啟動就在那一行掛掉，launchd 反覆重啟，
// 主 app 那頭永遠等不到回覆。內嵌 XPC service 的連線受理是由 launchd 接管的，
// listener 層的 requirement 設定不適用。
// 改成在 delegate 裡對**每一條進來的連線**設 requirement——同樣是系統層強制，
// 一樣不必自己查 pid（pid 會被回收再利用，是有名的 TOCTOU 弱點）。
final class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    private let callerVerification: CallerVerification.Mode

    init(callerVerification: CallerVerification.Mode) {
        self.callerVerification = callerVerification
    }

    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // 沒有驗證就不可以有執行能力（威脅模型 T7）。
        // 第 ④ 段把 willExecuteActions 翻成 true 的那一刻，這裡自動開始拒絕未驗證的連線。
        switch CallerVerification.decide(mode: callerVerification,
                                         serviceCanExecute: ExecutorService.willExecuteActions) {
        case .refuse(let reason):
            NSLog("CoPartnerExecutor 拒絕連線：%@", reason)
            return false
        case .accept:
            break
        }

        // 要求對方（主 app）符合 requirement。必須在 resume 之前設。
        if case .enforced(let requirement) = callerVerification {
            connection.setCodeSigningRequirement(requirement)
        }
        connection.exportedInterface = NSXPCInterface(with: ExecutorXPCProtocol.self)
        connection.exportedObject = ExecutorService(callerVerification: callerVerification)
        connection.resume()
        return true
    }
}

// 呼叫者必須是「同一個 Team 簽的、bundle id 為主 app」的程式（威脅模型 T7）。
let callerVerification = CodeSigningIdentity.requirement(
    forBundleIdentifier: CodeSigningIdentity.mainAppBundleID)

let listener = NSXPCListener.service()
let delegate = ServiceDelegate(callerVerification: callerVerification)
listener.delegate = delegate
listener.resume()
