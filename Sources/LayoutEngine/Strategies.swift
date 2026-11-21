import Foundation
import Geometry

/// Builds layout trees and chooses which layouts fit a situation.
struct Strategies {
    let prefs: LayoutPreferences

    func shape(of area: Rect) -> DisplayShape {
        let a = area.aspect
        if a > prefs.ultrawideAspect { return .ultrawide }
        if a < prefs.portraitAspect { return .portrait }
        return .landscape
    }

    /// The long axis: windows are split along it first.
    func primaryAxis(of area: Rect) -> Axis { area.w >= area.h ? .horizontal : .vertical }

    /// Ordered layout candidates for `count` windows. The first one is the
    /// smart default; cycling walks the rest. This table is the single source
    /// of truth for the defaults (mirrored by the tests).
    func candidates(count n: Int, area: Rect) -> [LayoutID] {
        guard n > 0 else { return [] }
        let s = shape(of: area)
        let columnsFit = (area.w - prefs.gap * Double(n - 1)) / Double(n) >= prefs.ultrawideColumnMinWidth

        let list: [LayoutID]
        switch (n, s) {
        case (1, .ultrawide): list = [.centered, .maximize]
        case (1, _): list = [.maximize, .centered]
        case (2, .portrait): list = [.rows, .columns]
        case (2, _): list = [.columns, .masterStack, .rows]
        case (3, .ultrawide): list = [.columns, .masterStack, .rows]
        case (3, .portrait): list = [.rows, .masterStack, .columns]
        case (3, _): list = [.masterStack, .columns, .rows]
        case (4, .ultrawide): list = columnsFit ? [.columns, .grid, .masterStack] : [.grid, .columns, .masterStack]
        case (4, .portrait): list = [.grid, .rows, .masterStack]
        case (4, _): list = [.grid, .masterStack, .columns]
        case (5, .ultrawide): list = columnsFit ? [.columns, .grid, .masterStack] : [.grid, .masterStack, .columns]
        case (5, _): list = [.grid, .masterStack, .bsp]
        case (6, _): list = [.grid, .masterStack, .bsp]
        default: list = [.grid, .masterStack]
        }
        return list.filter { $0.supports(count: n) }
    }

    /// The tree for `layout` with exactly `n` leaves.
    func tree(_ layout: LayoutID, count n: Int, area: Rect) -> LayoutNode {
        precondition(n >= 1)
        let axis = primaryAxis(of: area)
        switch layout {
        case .maximize:
            return .leaf(.master)

        case .centered:
            let f = min(1, max(0.2, prefs.centeredWidthFraction))
            let side = (1 - f) / 2
            if side <= 0 { return .leaf(.master) }
            return .split(.horizontal, [.spacer, .leaf(.master), .spacer], weights: [side, f, side])

        case .columns:
            return .even(.horizontal, count: n)

        case .rows:
            return .even(.vertical, count: n)

        case .masterStack:
            if n == 1 { return .leaf(.master) }
            let r = prefs.clampedMasterRatio
            return .split(
                axis, [.leaf(.master), .even(axis.flipped, count: n - 1, role: .stack)],
                weights: [r, 1 - r])

        case .grid:
            let (cols, rows) = gridDimensions(count: n, area: area)
            return gridTree(count: n, cols: cols, rows: rows)

        case .bsp:
            return bspTree(count: n, axis: axis)
        }
    }

    /// Picks (columns, rows) for a grid by minimising a cost:
    /// cell-aspect deviation + empty cells + cells that are too small.
    func gridDimensions(count n: Int, area: Rect) -> (cols: Int, rows: Int) {
        var best = (cols: 1, rows: n)
        var bestCost = Double.infinity
        // gridTree spreads windows evenly over rows, so the real column count
        // is ceil(n / rows). Score exactly those shapes.
        for rows in 1...n {
            let cols = Int((Double(n) / Double(rows)).rounded(.up))
            let cellW = (area.w - prefs.gap * Double(cols - 1)) / Double(cols)
            let cellH = (area.h - prefs.gap * Double(rows - 1)) / Double(rows)
            guard cellW > 0, cellH > 0 else { continue }
            let empty = Double(rows * cols - n)
            var cost = abs(log((cellW / cellH) / prefs.targetCellAspect))
            cost += 0.5 * empty / Double(n)
            cost += max(0, (prefs.minComfortableCell.w - cellW) / prefs.minComfortableCell.w)
            cost += max(0, (prefs.minComfortableCell.h - cellH) / prefs.minComfortableCell.h)
            if cost < bestCost - 1e-9 {
                bestCost = cost
                best = (cols, rows)
            }
        }
        return best
    }

    /// Rows of columns. Windows are spread evenly over the rows so there is
    /// never a lonely full-width window at the bottom (7 -> 3, 2, 2).
    func gridTree(count n: Int, cols: Int, rows: Int) -> LayoutNode {
        let rows = max(1, min(rows, n))
        let base = n / rows
        let extra = n % rows
        let rowNodes = (0..<rows).map { r in LayoutNode.even(.horizontal, count: base + (r < extra ? 1 : 0)) }
        if rowNodes.count == 1 { return rowNodes[0] }
        return .split(.vertical, rowNodes, weights: Array(repeating: 1, count: rowNodes.count))
    }

    /// First window takes half, the rest recurse into the other half with the
    /// split axis alternating.
    func bspTree(count n: Int, axis: Axis) -> LayoutNode {
        if n == 1 { return .leaf(.cell) }
        let first: LayoutNode = .leaf(.cell)
        return .split(axis, [first, bspTree(count: n - 1, axis: axis.flipped)], weights: [1, 1])
    }
}
