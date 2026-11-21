import Geometry

/// Pure, deterministic layout planner.
///
/// ```swift
/// let engine = LayoutEngine()
/// let plan = engine.plan(LayoutContext(area: visibleFrame, windows: windows))
/// // plan.frames[windowID] -> target frame
/// ```
public struct LayoutEngine: Sendable {
    public init() {}

    /// Ordered layout candidates for `count` windows in `area` (default first).
    public func candidates(count: Int, area: Rect, preferences: LayoutPreferences = .init()) -> [LayoutID] {
        Strategies(prefs: preferences).candidates(count: count, area: area.inset(by: preferences.outerPadding))
    }

    /// Computes target frames.
    /// - Parameters:
    ///   - layout: force a layout; falls back to the default if it can't hold the window count.
    ///   - rotation: shifts every window `rotation` slots forward from where it
    ///     is now (the "Rotate" action). While rotating, the focused window is
    ///     not pinned to the master slot, so repeated rotations cycle.
    /// - Returns: `nil` when there are no windows.
    public func plan(_ context: LayoutContext, layout requested: LayoutID? = nil, rotation: Int = 0) -> LayoutPlan? {
        let prefs = context.preferences
        let strategies = Strategies(prefs: prefs)
        let area = context.area.inset(by: prefs.outerPadding)

        let limit = max(1, prefs.maxWindows)
        let placed = Array(context.windows.prefix(limit))
        let unplaced = context.windows.dropFirst(limit).map(\.id)
        let n = placed.count
        guard n > 0, area.w > 0, area.h > 0 else { return nil }

        let candidates = strategies.candidates(count: n, area: area)
        let layout = requested.flatMap { $0.supports(count: n) ? $0 : nil } ?? candidates[0]
        let tree = strategies.tree(layout, count: n, area: area)
        let roles = tree.leafRoles
        let solver = FrameSolver(gap: prefs.gap)
        let assigner = SlotAssigner(focusedIsMaster: prefs.focusedIsMaster && rotation == 0)

        func mins(for slotToWindow: [Int]) -> [Size] {
            slotToWindow.map { w in
                let win = placed[w]
                return win.isResizable ? (win.minSize ?? .zero) : win.frame.size
            }
        }
        func movement(_ slotToWindow: [Int], _ frames: [Rect]) -> Double {
            zip(slotToWindow, frames).reduce(0) { acc, pair in
                let f = placed[pair.0].frame
                let t = pair.1
                return acc + abs(f.x - t.x) + abs(f.y - t.y) + abs(f.w - t.w) + abs(f.h - t.h)
            }
        }

        // Assign against unconstrained slots, solve with the assigned windows'
        // minimum sizes, then re-assign against the solved frames until the
        // assignment stops changing. Keep the iterate that moves windows least,
        // so arranging an already arranged screen is a no-op even when minimum
        // sizes shift the slots.
        var slots = solver.solve(tree, in: area, mins: Array(repeating: .zero, count: n)).frames
        var best: (assignment: [Int], solved: FrameSolver.Result, cost: Double)?
        var seen: Set<[Int]> = []
        for _ in 0..<4 {
            let assignment = assigner.assign(windows: placed, slots: slots, roles: roles, area: area)
            guard seen.insert(assignment).inserted else { break }
            let solved = solver.solve(tree, in: area, mins: mins(for: assignment))
            let cost = movement(assignment, solved.frames)
            if best == nil || cost < best!.cost - 1e-9 { best = (assignment, solved, cost) }
            slots = solved.frames
        }
        var slotToWindow = best!.assignment
        var solved = best!.solved

        // Rotate relative to the current arrangement.
        let k = ((rotation % n) + n) % n
        if k != 0 {
            var rotated = slotToWindow
            for s in 0..<n { rotated[(s + k) % n] = slotToWindow[s] }
            slotToWindow = rotated
            solved = solver.solve(tree, in: area, mins: mins(for: slotToWindow))
        }

        var frames: [WindowID: Rect] = [:]
        for (slot, w) in slotToWindow.enumerated() {
            let win = placed[w]
            var target = solved.frames[slot]
            if !win.isResizable {
                // Fixed-size windows keep their size and sit centred in the slot.
                target = target.centered(size: win.frame.size, clampedTo: area)
            }
            frames[win.id] = target
        }

        return LayoutPlan(
            layout: layout, candidates: candidates, frames: frames,
            unplaced: unplaced, isFeasible: solved.isFeasible)
    }
}
