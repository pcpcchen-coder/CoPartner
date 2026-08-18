// 執行端 XPC 的**拒絕路徑**探測（step 55 ②）。
//
// 用途：從一個「不是 CoPartner」的程序去敲 executor 的 endpoint，看會發生什麼事。
// 沒驗過拒絕路徑，就等於沒有那道防線——只驗過「自己人連得上」證明不了任何事。
//
// 用法（編成獨立執行檔再跑，才會是 ad-hoc 簽章、沒有 Team ID）：
//
//     swiftc -O -o /tmp/xpc-probe scripts/xpc-probe.swift
//     /tmp/xpc-probe
//
// 預期結果（兩種都算通過，但意義不同，請把實際輸出貼回來）：
//
//   A. 「連不上／找不到 service」
//      內嵌在 Contents/XPCServices 的 XPC service **只有它所屬的 app 定址得到**，
//      外部程序連名字都查不到。若是這種結果，T7 的主要防線其實是 service 的**類型**，
//      驗簽只是縱深防禦——這件事值得寫進威脅模型，不該含糊帶過。
//
//   B. 「連得上但被拒（invalid code signature / connection invalid）」
//      表示 endpoint 對外可見，而 code-signing requirement 真的擋住了它。
//
// 若出現 C.「連得上而且拿到自檢報告」——那是**防線沒生效**，要停下來修。
import Foundation

@objc(ExecutorXPCProtocol) protocol ExecutorXPCProtocol {
    func perform(requestJSON: Data, withReply reply: @escaping (Data?) -> Void)
}

let serviceName = "com.pcpcchen.copartner.CoPartnerExecutor"
print("探測 \(serviceName)（本程序 pid \(ProcessInfo.processInfo.processIdentifier)，euid \(geteuid())）")

let connection = NSXPCConnection(serviceName: serviceName)
connection.remoteObjectInterface = NSXPCInterface(with: ExecutorXPCProtocol.self)

let done = DispatchSemaphore(value: 0)
// 只送自檢請求：它在協定上就不是一個動作，探測本身不可能造成任何副作用。
let payload = Data(#"{"actionID":"00000000-0000-0000-0000-000000000000","generation":0,"kind":{"selfTest":{}}}"#.utf8)

connection.interruptionHandler = { print("結果：連線中斷（interrupted）"); done.signal() }
connection.invalidationHandler = { print("結果：連線失效（invalidated）— 多半是外部程序定址不到內嵌 service"); done.signal() }
connection.resume()

let proxy = connection.remoteObjectProxyWithErrorHandler { error in
    print("結果：被拒或無法連線 — \(error.localizedDescription)")
    done.signal()
}
if let service = proxy as? ExecutorXPCProtocol {
    service.perform(requestJSON: payload) { data in
        if let data, let text = String(data: data, encoding: .utf8) {
            print("⚠️ 結果：連得上而且拿到回覆 —— 防線沒生效，要停下來修")
            print("   回覆：\(text)")
        } else {
            print("結果：連得上但回覆是空的")
        }
        done.signal()
    }
} else {
    print("結果：proxy 不符合協定")
    done.signal()
}

if done.wait(timeout: .now() + 10) == .timedOut {
    print("結果：10 秒無回應（逾時）")
}
connection.invalidate()
