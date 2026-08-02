import SwiftUI
import KeyboardShortcuts
// 設定視窗（step 10.5）：讓使用者自訂全域熱鍵。
// KeyboardShortcuts.Recorder 會自動把使用者錄的組合鍵持久化到 UserDefaults，
// 預設值沿用 AppCoordinator 定義的 ⌃⌥⌘O / ⌃⌥⌘.，使用者可覆蓋、可清除還原。

struct SettingsView: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("切換觀察（開始 / 停止）：", name: .toggleObserve)
            KeyboardShortcuts.Recorder("緊急停止：", name: .emergencyStop)
            Text("點右側欄位後按下想要的組合鍵即可錄製；按清除鈕則還原預設。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 400)
    }
}
