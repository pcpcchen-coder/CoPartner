import Foundation

// XPC service 進入點（🔒 真機膠水）。
//
// `NSXPCListener.service()` 會阻塞並接管這個程序的生命週期——
// 由 launchd 依需求啟動、閒置時回收，主 app 不需要自己管 spawn 與收屍。
final class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // 🔒 第 ② 段要在這裡驗呼叫者的 code-signing requirement（威脅模型 T7）。
        // 目前一律接受——安全性此刻不靠這道檢查，而是靠 ExecutorService 沒有執行能力。
        // ⚠️ 加上真執行（第 ④ 段）之前，這個 return true 必須先變成真的驗證。
        connection.exportedInterface = NSXPCInterface(with: ExecutorXPCProtocol.self)
        connection.exportedObject = ExecutorService()
        connection.resume()
        return true
    }
}

let delegate = ServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
