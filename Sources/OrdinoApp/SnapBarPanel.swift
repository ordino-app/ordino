import AppKit
import Geometry
import LayoutEngine
import SwiftUI

/// What the snap bar highlights: the group and cell under the cursor.
@MainActor
@Observable
final class SnapBarModel {
    var hoveredGroup: Int?
    var hoveredAction: WindowAction?
}

/// The bar of layouts shown at the top of the screen while dragging a window (see `SnapBar`).
/// It never takes the mouse: the drag stays with macOS, ordino hit-tests the cursor itself.
@MainActor
final class SnapBarPanel: NSPanel {
    let model = SnapBarModel()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        contentView = NSHostingView(rootView: SnapBarView(model: model))
    }

    /// Shows the bar at `bar` (Quartz coordinates) with the hovered cell highlighted.
    func show(quartzFrame bar: Rect, hovered: (group: Int, action: WindowAction)?) {
        model.hoveredGroup = hovered?.group
        model.hoveredAction = hovered?.action
        let frame = NSRect(x: bar.x, y: SnapPreviewPanel.primaryHeight - bar.y - bar.h, width: bar.w, height: bar.h)
        if self.frame != frame { setFrame(frame, display: true) }
        if !isVisible { orderFrontRegardless() }
    }
}

private struct SnapBarView: View {
    let model: SnapBarModel

    var body: some View {
        HStack(spacing: SnapBar.gap) {
            ForEach(Array(SnapBar.groups.enumerated()), id: \.offset) { index, cells in
                GroupView(cells: cells, hovered: model.hoveredGroup == index ? model.hoveredAction : nil)
                    .frame(width: SnapBar.groupSize.w, height: SnapBar.groupSize.h)
            }
        }
        .padding(SnapBar.padding)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(
                Color.primary.opacity(0.12), lineWidth: 0.5)
        )
    }
}

private struct GroupView: View {
    let cells: [SnapBar.Cell]
    let hovered: WindowAction?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, c in
                    let on = c.action == hovered
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(on ? Color.accentColor : Color.primary.opacity(0.14))
                        .frame(
                            width: max(1, c.unit.w * geo.size.width - SnapBar.cellGap),
                            height: max(1, c.unit.h * geo.size.height - SnapBar.cellGap)
                        )
                        .offset(
                            x: c.unit.x * geo.size.width + SnapBar.cellGap / 2,
                            y: c.unit.y * geo.size.height + SnapBar.cellGap / 2
                        )
                        .animation(.easeOut(duration: 0.1), value: on)
                }
            }
        }
    }
}
