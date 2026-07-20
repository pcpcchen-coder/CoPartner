import XCTest
import CaptureEngine

/// 擷取黑名單（§G）：source 排除密碼管理器/銀行/自身 app；includeList 空回 nil 防空陣列 bug。
final class CaptureBlacklistTests: XCTestCase {
    private struct FakeApp { let bundle: String?; let name: String }
    private let list = CaptureBlacklist(ownBundleID: "com.copartner.app")

    private func include(_ apps: [FakeApp]) -> [FakeApp]? {
        list.includeList(allApps: apps, bundleID: { $0.bundle }, name: { $0.name })
    }

    func testDefaultListBlocksPasswordManagers() {
        XCTAssertTrue(list.isBlocked(bundleID: "com.1password.1password", appName: "1Password"))
        XCTAssertTrue(list.isBlocked(bundleID: "com.apple.keychainaccess", appName: "Keychain Access"))
    }

    func testNamePatternCaseInsensitive() {
        XCTAssertTrue(list.isBlocked(bundleID: "com.acme.x", appName: "My BANK App"))    // 含 "bank"
        XCTAssertTrue(list.isBlocked(bundleID: nil, appName: "網路銀行 - 密碼"))
    }

    func testOwnAppAlwaysExcluded() {
        XCTAssertTrue(list.isBlocked(bundleID: "com.copartner.app", appName: "CoPartner"))
    }

    func testNonBlockedPasses() {
        XCTAssertFalse(list.isBlocked(bundleID: "com.apple.Safari", appName: "Safari"))
    }

    func testIncludeListDropsBlocked() {
        let apps = [FakeApp(bundle: "com.apple.Safari", name: "Safari"),
                    FakeApp(bundle: "com.1password.1password", name: "1Password"),
                    FakeApp(bundle: "com.copartner.app", name: "CoPartner")]
        let kept = include(apps)
        XCTAssertEqual(kept?.map { $0.name }, ["Safari"])
    }

    func testEmptyIncludeListReturnsNilNotEmpty() {
        // 全部被擋 → nil（「這幀別開 stream」），不是空陣列（避開 SCContentFilter 空陣列 bug）。
        let apps = [FakeApp(bundle: "com.1password.1password", name: "1Password"),
                    FakeApp(bundle: "com.copartner.app", name: "CoPartner")]
        XCTAssertNil(include(apps))
    }
}
