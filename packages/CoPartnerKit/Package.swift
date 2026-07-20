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
    ],
    dependencies: [
        // 全域熱鍵（V2-B.5）
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
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
        .testTarget(name: "CoPartnerKitTests", dependencies: ["CoPartnerCore", "CaptureEngine", "ScriptNarrator", "CloudRouter", "MemoryStore"]),
    ]
)
