import Geometry

/// The bar of small layouts that slides in at the top of the screen while a window is dragged near it
/// (like Windows 11). Each layout is a group of cells; each cell is a target area: hovering it while
/// dragging previews that placement, releasing there applies it.
public enum SnapBar {
    public struct Cell: Sendable, Equatable {
        public let action: WindowAction
        /// Position inside its group, as fractions (0...1) of the group's box.
        public let unit: Rect
    }

    /// Layouts for a landscape display.
    public static let landscape: [[Cell]] = [
        [cell(.leftHalf, 0, 0, 0.5, 1), cell(.rightHalf, 0.5, 0, 0.5, 1)],
        [
            cell(.firstThird, 0, 0, 1 / 3.0, 1), cell(.centerThird, 1 / 3.0, 0, 1 / 3.0, 1),
            cell(.lastThird, 2 / 3.0, 0, 1 / 3.0, 1),
        ],
        [cell(.firstTwoThirds, 0, 0, 2 / 3.0, 1), cell(.lastThird, 2 / 3.0, 0, 1 / 3.0, 1)],
        [cell(.firstThird, 0, 0, 1 / 3.0, 1), cell(.lastTwoThirds, 1 / 3.0, 0, 2 / 3.0, 1)],
        [
            cell(.topLeft, 0, 0, 0.5, 0.5), cell(.topRight, 0.5, 0, 0.5, 0.5),
            cell(.bottomLeft, 0, 0.5, 0.5, 0.5), cell(.bottomRight, 0.5, 0.5, 0.5, 0.5),
        ],
        [cell(.maximize, 0, 0, 1, 1)],
    ]

    /// Layouts for a portrait display: halves top and bottom, thirds as rows (the engine turns thirds into
    /// rows on portrait displays, so the cells are drawn transposed to match).
    public static let portrait: [[Cell]] = landscape.map { cells in
        cells.map { c in
            let unit =
                c.action == .topLeft || c.action == .topRight || c.action == .bottomLeft
                    || c.action == .bottomRight || c.action == .maximize
                ? c.unit : Rect(x: c.unit.y, y: c.unit.x, w: c.unit.h, h: c.unit.w)
            let action: WindowAction =
                switch c.action {
                case .leftHalf: .topHalf
                case .rightHalf: .bottomHalf
                default: c.action
                }
            return Cell(action: action, unit: unit)
        }
    }

    public static func groups(portrait isPortrait: Bool) -> [[Cell]] { isPortrait ? portrait : landscape }

    /// Kept for callers that don't care about orientation (same count of groups either way).
    public static var groups: [[Cell]] { landscape }

    // Bar geometry in points.
    public static let groupSize = Size(w: 72, h: 46)
    public static let gap: Double = 10
    public static let padding: Double = 10
    public static let cellGap: Double = 2
    /// How far below the top of the usable area the cursor brings the bar in.
    public static let reach: Double = 140

    public static var size: Size {
        let n = Double(groups.count)
        return Size(w: padding * 2 + n * groupSize.w + (n - 1) * gap, h: padding * 2 + groupSize.h)
    }

    /// The bar's frame on a display: centred, just below the top of the usable area.
    public static func frame(in visible: Rect) -> Rect {
        Rect(x: visible.x + (visible.w - size.w) / 2, y: visible.y + 8, w: size.w, h: size.h)
    }

    /// Frame of a group's box inside the bar frame.
    public static func groupFrame(_ index: Int, in bar: Rect) -> Rect {
        Rect(
            x: bar.x + padding + Double(index) * (groupSize.w + gap), y: bar.y + padding,
            w: groupSize.w, h: groupSize.h)
    }

    /// Frame of a cell inside its group's box (with a small gap between cells).
    public static func cellFrame(_ c: Cell, in group: Rect) -> Rect {
        Rect(
            x: group.x + c.unit.x * group.w + cellGap / 2, y: group.y + c.unit.y * group.h + cellGap / 2,
            w: c.unit.w * group.w - cellGap, h: c.unit.h * group.h - cellGap)
    }

    /// Whether the bar should be shown for a cursor at y on a display with usable area `visible`.
    public static func isShown(cursorY y: Double, visible: Rect) -> Bool {
        y <= visible.y + reach
    }

    /// The cell under the cursor (group index, cell), or nil. Gaps between groups count as nothing.
    public static func hit(x: Double, y: Double, bar: Rect, portrait: Bool = false) -> (group: Int, cell: Cell)? {
        for (i, cells) in groups(portrait: portrait).enumerated() {
            let g = groupFrame(i, in: bar)
            guard g.contains(pointX: x, y: y) else { continue }
            // Nearest cell, so the hairline gaps inside a group never drop the target.
            for c in cells {
                let r = Rect(x: g.x + c.unit.x * g.w, y: g.y + c.unit.y * g.h, w: c.unit.w * g.w, h: c.unit.h * g.h)
                if r.contains(pointX: x, y: y) { return (i, c) }
            }
        }
        return nil
    }

    private static func cell(_ a: WindowAction, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Cell {
        Cell(action: a, unit: Rect(x: x, y: y, w: w, h: h))
    }
}
