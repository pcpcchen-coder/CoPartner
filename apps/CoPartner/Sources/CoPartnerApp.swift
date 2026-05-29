import SwiftUI
import CoPartnerCore
// 設計：docs/design/v1_full-design.md §A.2（程序拓樸）；menu bar 為主程序（LSUIElement）

@main
struct CoPartnerApp: App {
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra("CoPartner", systemImage: coordinator.statusIcon) {
            MenuBarContentView()
                .environmentObject(coordinator)
        }
        .menuBarExtraStyle(.window)
    }
}
