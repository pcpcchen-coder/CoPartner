// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CoPartnerKit",
    platforms: [.macOS(.v15)], // 開發目標 macOS 26；.v15 為 SPM 最低，FoundationModels 於執行期用 #available 守門
    products: [
        .library(name: "CoPartnerCore", targets: ["CoPartnerCore"]),
        .library(name: "CaptureEngine", targets: ["CaptureEngine"]),
        .library(name: "ScriptNarrator", targets: ["ScriptNarrator"]),
        .library(name: "MemoryStore", targets: ["MemoryStore"]),
        .library(name: "CloudRouter", targets: ["CloudRouter"]),
        .library(name: "ActionExecutor", targets: ["ActionExecutor"]),
        // 印 sbpl profile 的小工具：讓 scripts/sandbox-verify.sh 驗的是 app 真正會用的
        // 那份 profile，而不是腳本自己拼一份長得很像的。
        .executable(name: "copartner-sbpl", targets: ["SbplTool"]),
    ],
    dependencies: [
        // 註：全域熱鍵（V2-B.5）的 KeyboardShortcuts 只有 app target 用得到，由
        // apps/CoPartner/project.yml 直接宣告；這裡不重複宣告，否則 SPM 會警告
        // 「dependency 'keyboardshortcuts' is not used by any target」。
        // 註：sqlite-vec 透過 system library / SQLite 擴充載入，於 MemoryStore 內處理
    ],
    targets: [
        .target(name: "CoPartnerCore"),
        .target(name: "CaptureEngine", dependencies: ["CoPartnerCore"],
                resources: [.process("Resources")]),   // TileHash.metal → module bundle（Bundle.module）
        .target(name: "ScriptNarrator", dependencies: ["CoPartnerCore"]),
        .target(name: "MemoryStore", dependencies: ["CoPartnerCore"]),
        .target(name: "CloudRouter", dependencies: ["CoPartnerCore"]),
        .target(name: "ActionExecutor", dependencies: ["CoPartnerCore"]),
        .executableTarget(name: "SbplTool", dependencies: ["ActionExecutor"]),
        .testTarget(name: "CoPartnerKitTests", dependencies: ["CoPartnerCore", "CaptureEngine", "ScriptNarrator", "CloudRouter", "MemoryStore", "ActionExecutor"]),
    ]
)
