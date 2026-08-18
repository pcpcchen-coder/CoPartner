import Foundation
// 主 app 與 XPC service **共用**這個檔（project.yml 裡兩個 target 都收 Shared/）。
// 協定不一致是 XPC 最典型的無聲失敗：連線建得起來，呼叫卻永遠不回。
//
// 為什麼線上型別是 `Data` 而不是一堆 @objc 值：
// NSXPC 的 @objc 協定只吃 ObjC 相容型別，要傳結構化資料就得走 NSSecureCoding
// 加一長串 class 白名單，而那些型別無法在 SPM 套件裡以純 Swift 值測試。
// 改成「一包 JSON」之後，**契約本身（ExecutionWire）完全在 CI 驗**，
// 跨程序這段只剩連線膠水是盲寫的。

/// service 的 bundle identifier，也是 `NSXPCConnection(serviceName:)` 用的名字。
/// 寫成共用常數而不是兩邊各打一次字串——打錯的話是執行期才炸，而且訊息不明顯。
enum ExecutorXPCService {
    static let name = "com.pcpcchen.copartner.CoPartnerExecutor"
}

/// service 對外暴露的介面。
///
/// ⚠️ 這個 endpoint 在第 ① 段是**沒有呼叫者驗證**的：任何本機程序都連得上。
/// 之所以現在安全，是因為 service 這一段**完全沒有執行任何東西的程式碼**——
/// 不是靠檢查擋住，是靠「根本沒有那個能力」。
/// 第 ② 段補上 code-signing requirement 驗證之後，才輪到「靠檢查擋住」。
/// 順序刻意如此：先讓 endpoint 無害，再讓它有能力。
/// `@objc(...)` 明寫執行期名稱：NSXPC 是靠這個名字對協定的，
/// 讓它依賴 Swift 的預設命名規則等於把一個無聲失敗的機會留在那裡。
@objc(ExecutorXPCProtocol) protocol ExecutorXPCProtocol {
    /// 送一包 `ExecutionRequest` 的 JSON，回一包 `ExecutionOutcome` 的 JSON。
    ///
    /// 回覆用 `Data?` 而非 throws：XPC 的錯誤語意（連線中斷、對方崩潰）跟
    /// 「service 明確拒絕」是兩回事，混在一起會讓呼叫端分不出「沒接上」和「被拒」。
    /// nil 代表 service 連回覆都編不出來——呼叫端一律當成失敗處理。
    func perform(requestJSON: Data, withReply reply: @escaping (Data?) -> Void)
}
