import SwiftUI

// 會自動換行的按鈕列。
//
// ## 為什麼需要它
//
// 這個面板的按鈕原本是單一 `HStack`，而每加一顆除錯按鈕，我就把 `.frame(width:)`
// 調大一次：760 → 840 → 920 → 1000 → 1080，註解每次都寫「按鈕被擠出畫面重演過兩次，
// 寧可先留寬」。
//
// **那個做法本身造成了真機上的下一個失敗**：`MenuBarExtra` 的面板錨定在選單列圖示
// 底下，圖示在螢幕中間偏右時，1080 寬的面板左半邊會落在螢幕外——按鈕不但看不見，
// 整個面板還移不動（它不是可拖曳的視窗）。
//
// 「寧可留寬」修的是「按鈕被擠到下面看不見」，卻換來「按鈕被推到螢幕外看不見」。
// 同一個症狀、相反的成因，而每次補一個新的寬度只是把它推到下一顆按鈕再爆。
//
// 所以改成結構上不會再發生：**寬度固定，按鈕自己換行**。之後再加幾顆都不必動版面。
struct WrappingButtonRow: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 6

    /// 一列的內容與高度。排版與量測共用同一份計算——分開寫的話，
    /// 量到的高度與畫出來的行數遲早會不一致，而那表現成「最後一列被切掉」。
    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var result: [Row] = []
        var current = Row()
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let candidate = current.indices.isEmpty
                ? size.width
                : current.width + horizontalSpacing + size.width
            // 已經有東西、又放不下 → 換行。空列一律收下，否則超寬的單顆按鈕會無限換行。
            if !current.indices.isEmpty, candidate > maxWidth {
                result.append(current)
                current = Row(indices: [index], width: size.width, height: size.height)
            } else {
                current.indices.append(index)
                current.width = candidate
                current.height = max(current.height, size.height)
            }
        }
        if !current.indices.isEmpty { result.append(current) }
        return result
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let laid = rows(for: subviews, maxWidth: maxWidth)
        let height = laid.map(\.height).reduce(0, +)
            + verticalSpacing * CGFloat(max(0, laid.count - 1))
        let width = laid.map(\.width).max() ?? 0
        return CGSize(width: maxWidth.isFinite ? maxWidth : width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        let laid = rows(for: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in laid {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size))
                x += size.width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }
}
