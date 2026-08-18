import Foundation
import ActionExecutor

// XPC service 進入點（🔒 真機膠水）。
//
// `NSXPCListener.service()` 會阻塞並接管這個程序的生命週期——
// 由 launchd 依需求啟動、閒置時回收，主 app 不需要自己管 spawn 與收屍。
final class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    private let callerVerification: CallerVerification.Mode

    init(callerVerification: CallerVerification.Mode) {
        self.callerVerification = callerVerification
    }

    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // requirement 若組得出來，系統已在**連線層**擋掉不符者（見下方 setConnectionCodeSigningRequirement），
        // 能走到這裡就代表對方符合。組不出來時（ad-hoc 組建無 Team ID）則由這條規則決定：
        // 沒有驗證就不可以有執行能力。
        switch CallerVerification.decide(mode: callerVerification,
                                         serviceCanExecute: ExecutorService.willExecuteActions) {
        case .refuse(let reason):
            NSLog("CoPartnerExecutor 拒絕連線：%@", reason)
            return false
        case .accept:
            break
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
if case .enforced(let requirement) = callerVerification {
    // 交給系統在連線層強制：比自己在 delegate 裡查 pid 可靠得多——
    // pid 會被回收再利用，用 pid 查身分是有名的 TOCTOU 弱點。
    listener.setConnectionCodeSigningRequirement(requirement)
}
let delegate = ServiceDelegate(callerVerification: callerVerification)
listener.delegate = delegate
listener.resume()
