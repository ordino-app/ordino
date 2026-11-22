import Geometry

/// Where a window dragged to a screen edge snaps (Windows-style).
public enum SnapZone {
    /// The snap action for a cursor at (x, y) on a display frame (Quartz coordinates, origin top-left),
    /// or nil away from the edges. Corners win over edges; the bottom edge alone does nothing (the Dock).
    /// - Parameters:
    ///   - edge: how close (points) to an edge the cursor must be.
    ///   - corner: how far along an edge from a corner still counts as that corner.
    public static func action(x px: Double, y py: Double, in f: Rect, edge: Double = 6, corner: Double = 48)
        -> WindowAction?
    {
        let nearLeft = px - f.x <= edge
        let nearRight = f.x + f.w - px <= edge
        let nearTop = py - f.y <= edge
        let nearBottom = f.y + f.h - py <= edge
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
}
