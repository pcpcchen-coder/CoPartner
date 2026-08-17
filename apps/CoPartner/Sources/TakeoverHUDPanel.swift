import AppKit
import SwiftUI
import ActionExecutor

// 常駐浮層的視窗殼（🔒 真機目測於 step 53）。
//
// CoPartner 是 LSUIElement menu bar app——沒有主視窗可以掛 sheet，
// 所以接手 HUD 必須自己開一個 NSPanel。三個關鍵設定：
//   .floating       浮在其他 app 之上——接手時使用者正在別的 app 裡，HUD 被蓋住就等於沒有閘門
//   .nonactivating  顯示 HUD 不搶走前景 app 的焦點（搶焦點會打斷使用者正在做的事，
//                   而且 Claude 的動作是對前景 app 下的，焦點一換座標語意就變了）
//   canJoinAllSpaces 跨 Space 顯示——使用者切到別的桌面時 HUD 不該消失
@MainActor
final class TakeoverHUDPanel {
    private var panel: NSPanel?

    /// 顯示（或更新）浮層。
    func show(_ presentation: TakeoverHUDPresentation,
              onDecision: @escaping (TakeoverHUDPresentation.Decision) -> Void) {
        let view = TakeoverHUDView(presentation: presentation, onDecision: onDecision)
        let hosting = NSHostingView(rootView: view)

        if let panel {
            panel.contentView = hosting
            panel.setContentSize(hosting.fittingSize)
            return                                   // 已顯示 → 就地換內容，不重新定位（避免跳動）
        }

        let p = NSPanel(contentRect: .zero,
                        styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                        backing: .buffered,
                        defer: false)
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.hidesOnDeactivate = false                  // 切到別的 app 時不可消失——那正是要顯示的時機
        p.contentView = hosting
        p.setContentSize(hosting.fittingSize)
        positionTopRight(p)
        // orderFrontRegardless：不啟用 app 也要顯示（配合 .nonactivating 不搶焦點）
        p.orderFrontRegardless()
        panel = p
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    /// 放在主螢幕右上角、選單列下方——不擋住使用者正在操作的內容區。
    private func positionTopRight(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let margin: CGFloat = 20
        let visible = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(CGPoint(x: visible.maxX - size.width - margin,
                                     y: visible.maxY - size.height - margin))
    }
}
