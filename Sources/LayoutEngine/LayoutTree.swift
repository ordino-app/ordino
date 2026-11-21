import Geometry

/// Role of a slot. Used for "focused window becomes master".
public enum SlotRole: Sendable, Hashable {
    case master
    case stack
    case cell
}

/// Every layout is a tree of splits. Frames are derived from the tree, which
/// makes minimum-size repair one generic algorithm instead of one per layout.
public indirect enum LayoutNode: Sendable, Hashable {
    /// A slot that receives one window.
    case leaf(SlotRole)
    /// Empty space that receives no window (used by `.centered`).
    case spacer
    /// Children laid out along `axis`, sized by relative `weights`.
    case split(Axis, [LayoutNode], weights: [Double])

    /// `count` equally weighted leaves along `axis`.
    public static func even(_ axis: Axis, count: Int, role: SlotRole = .cell) -> LayoutNode {
        if count == 1 { return .leaf(role) }
        return .split(
            axis, Array(repeating: .leaf(role), count: count),
            weights: Array(repeating: 1, count: count))
    }

    public var leafCount: Int {
        switch self {
        case .leaf: 1
        case .spacer: 0
        case .split(_, let children, _): children.reduce(0) { $0 + $1.leafCount }
        }
    }

    /// Roles of all leaves in depth-first order (the slot order).
    public var leafRoles: [SlotRole] {
        switch self {
        case .leaf(let role): [role]
        case .spacer: []
        case .split(_, let children, _): children.flatMap(\.leafRoles)
        }
    }
}

/// Turns a ``LayoutNode`` into concrete frames, honouring per-leaf minimum sizes.
struct FrameSolver {
    let gap: Double

    struct Result {
        var frames: [Rect]
        var isFeasible: Bool
    }

    /// - Parameter mins: minimum size per leaf, in leaf order. Use `.zero` for none.
    func solve(_ node: LayoutNode, in rect: Rect, mins: [Size]) -> Result {
        precondition(mins.count == node.leafCount, "one min size per leaf")
        var frames = Array(repeating: Rect.zero, count: mins.count)
        var feasible = true
        var cursor = 0
        layout(node, in: rect, mins: mins, cursor: &cursor, frames: &frames, feasible: &feasible)
        return Result(frames: frames, isFeasible: feasible)
    }

    /// Minimum size a subtree needs, given the gap between siblings.
    func minimumSize(of node: LayoutNode, mins: [Size], start: Int) -> Size {
        switch node {
        case .leaf:
            return mins[start]
        case .spacer:
            return .zero
        case .split(let axis, let children, _):
            var index = start
            var along = 0.0
            var across = 0.0
            for child in children {
                let m = minimumSize(of: child, mins: mins, start: index)
                index += child.leafCount
                if axis == .horizontal {
                    along += m.w
                    across = max(across, m.h)
                } else {
                    along += m.h
                    across = max(across, m.w)
                }
            }
            along += gap * Double(max(0, children.count - 1))
            return axis == .horizontal ? Size(w: along, h: across) : Size(w: across, h: along)
        }
    }

    private func layout(
        _ node: LayoutNode, in rect: Rect, mins: [Size],
        cursor: inout Int, frames: inout [Rect], feasible: inout Bool
    ) {
        switch node {
        case .leaf:
            let m = mins[cursor]
            if m.w > rect.w + 0.5 || m.h > rect.h + 0.5 { feasible = false }
            frames[cursor] = rect
            cursor += 1

        case .spacer:
            break

        case .split(let axis, let children, let weights):
            precondition(children.count == weights.count, "one weight per child")
            let length = rect.length(along: axis)
            let available = max(0, length - gap * Double(max(0, children.count - 1)))

            var childMins: [Double] = []
            var index = cursor
            for child in children {
                let m = minimumSize(of: child, mins: mins, start: index)
                index += child.leafCount
                childMins.append(axis == .horizontal ? m.w : m.h)
            }

            let (shares, ok) = Self.distribute(available, weights: weights, mins: childMins)
            if !ok { feasible = false }

            var offset = axis == .horizontal ? rect.x : rect.y
            for (child, share) in zip(children, shares) {
                let childRect =
                    axis == .horizontal
                    ? Rect(x: offset, y: rect.y, w: share, h: rect.h)
                    : Rect(x: rect.x, y: offset, w: rect.w, h: share)
                layout(child, in: childRect, mins: mins, cursor: &cursor, frames: &frames, feasible: &feasible)
                offset += share + gap
            }
        }
    }

    /// Splits `available` by `weights`, but never gives a child less than its
    /// minimum (water-filling). If the minimums don't fit, they are scaled down
    /// proportionally and the result is flagged infeasible.
    /// Smallest share a child gets when minimums cannot all be honoured.
    static let minimumShare = 160.0

    static func distribute(_ available: Double, weights: [Double], mins: [Double]) -> ([Double], Bool) {
        let n = weights.count
        guard n > 0 else { return ([], true) }
        let totalMin = mins.reduce(0, +)
        if totalMin > available + 0.5 {
            // Infeasible: every child keeps a floor so no window collapses to 0,
            // and only the part of each minimum above the floor is scaled down.
            let floor = min(available / Double(n), minimumShare)
            let raised = mins.map { max($0, floor) }
            let excess = raised.reduce(0, +) - floor * Double(n)
            let room = max(0, available - floor * Double(n))
            let scale = excess > 0 ? room / excess : 0
            return (raised.map { floor + ($0 - floor) * scale }, false)
        }

        var fixed = Array(repeating: false, count: n)
        var shares = Array(repeating: 0.0, count: n)
        while true {
            let freeIdx = (0..<n).filter { !fixed[$0] }
            let fixedTotal = (0..<n).filter { fixed[$0] }.reduce(0.0) { $0 + mins[$1] }
            let remaining = available - fixedTotal
            let freeWeight = freeIdx.reduce(0.0) { $0 + max(0, weights[$1]) }
            var changed = false
            for i in freeIdx {
                let share =
                    freeWeight > 0
                    ? remaining * max(0, weights[i]) / freeWeight
                    : remaining / Double(freeIdx.count)
                if share < mins[i] - 1e-9 {
                    fixed[i] = true
                    changed = true
                } else {
                    shares[i] = share
                }
            }
            if !changed { break }
        }
        for i in 0..<n where fixed[i] { shares[i] = mins[i] }
        return (shares, true)
    }
}
