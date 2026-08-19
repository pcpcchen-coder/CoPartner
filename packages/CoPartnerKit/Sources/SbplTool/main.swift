import Foundation
import ActionExecutor

// 印出 sbpl profile 的小工具。**存在的唯一理由是單一事實來源**：
// `scripts/sandbox-verify.sh` 要驗的必須是 app 真正會用的那份 profile，
// 而不是腳本自己拼一份長得很像的。
//
// （`scripts/xpc-probe.swift` 的手寫 JSON 就踩過這個坑，最後靠一條測試綁住兩者。
//   這裡從一開始就不讓它們分家。）
//
// 用法：
//   swift run --package-path packages/CoPartnerKit copartner-sbpl \
//       --workspace /tmp/ws --exec /bin/cat --exec /usr/bin/touch --deny /tmp/ws/.secrets

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

var workspace: String?
var execAllowlist: [String] = []
var denied: [String] = []
var includeRuntimeMinimum = true

var arguments = Array(CommandLine.arguments.dropFirst())
while let flag = arguments.first {
    arguments.removeFirst()
    switch flag {
    case "--workspace":
        guard let value = arguments.first else { fail("--workspace 缺少值") }
        arguments.removeFirst(); workspace = value
    case "--exec":
        guard let value = arguments.first else { fail("--exec 缺少值") }
        arguments.removeFirst(); execAllowlist.append(value)
    case "--deny":
        guard let value = arguments.first else { fail("--deny 缺少值") }
        arguments.removeFirst(); denied.append(value)
    case "--no-runtime-minimum":
        // 給驗證腳本用：證明「少了 runtime 最小集合，連正向案例都跑不起來」。
        includeRuntimeMinimum = false
    default:
        fail("未知參數：\(flag)")
    }
}

guard let workspace else { fail("必須指定 --workspace") }

do {
    let profile = try SbplProfileBuilder().profile(execAllowlist: execAllowlist,
                                                   workspace: workspace,
                                                   deniedSubpaths: denied,
                                                   includeRuntimeMinimum: includeRuntimeMinimum)
    print(profile)
} catch {
    // 路徑不安全時**不印出任何 profile**——印一份「盡力而為」的比失敗更危險。
    fail("無法產生 profile：\(error)")
}
