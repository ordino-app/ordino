import Geometry

/// Where a window dragged to a screen edge snaps (Windows-style).
public enum SnapZone {
    /// The snap action for a cursor at (x, y) on a display frame (Quartz coordinates, origin top-left),
    /// or nil away from the edges. Corners win over edges; the bottom edge alone does nothing (the Dock).
    /// - Parameters:
    ///   - edge: how close (points) to an edge the cursor must be.
    ///   - corner: how far along an edge from a corner still counts as that corner. Small on purpose: a window
    ///     dragged by its title bar near the top must snap to a half, not a quarter (the cursor sits ~40 pt down).
    ///   - others: the other displays' frames. An edge another display touches is a doorway, not an edge:
    ///     the cursor passes through it when moving a window between displays, so it never snaps there.
    public static func action(
        x px: Double, y py: Double, in f: Rect, others: [Rect] = [], edge: Double = 6, corner: Double = 24
    ) -> WindowAction? {
        func open(_ side: Side) -> Bool { !others.contains { touches($0, f, side) } }
        let nearLeft = px - f.x <= edge && open(.left)
        let nearRight = f.x + f.w - px <= edge && open(.right)
        let nearTop = py - f.y <= edge && open(.top)
        let nearBottom = f.y + f.h - py <= edge && open(.bottom)
        let topBand = py - f.y <= corner
        let bottomBand = f.y + f.h - py <= corner
        let leftBand = px - f.x <= corner
        let rightBand = f.x + f.w - px <= corner
        if (nearLeft && topBand) || (nearTop && leftBand) { return .topLeft }
        if (nearRight && topBand) || (nearTop && rightBand) { return .topRight }
        if (nearLeft && bottomBand) || (nearBottom && leftBand) { return .bottomLeft }
        if (nearRight && bottomBand) || (nearBottom && rightBand) { return .bottomRight }
        if nearLeft { return .leftHalf }
        if nearRight { return .rightHalf }
        if nearTop { return .maximize }
        return nil
    }

    enum Side { case left, right, top, bottom }

    /// Whether display `o` sits against side `side` of display `f` (shares that edge, overlapping along it).
    static func touches(_ o: Rect, _ f: Rect, _ side: Side) -> Bool {
        let tol = 2.0
        let overlapY = o.y < f.y + f.h && o.y + o.h > f.y
        let overlapX = o.x < f.x + f.w && o.x + o.w > f.x
        switch side {
        case .left: return overlapY && abs(o.x + o.w - f.x) <= tol
        case .right: return overlapY && abs(f.x + f.w - o.x) <= tol
        case .top: return overlapX && abs(o.y + o.h - f.y) <= tol
        case .bottom: return overlapX && abs(f.y + f.h - o.y) <= tol
        }
    }
}
