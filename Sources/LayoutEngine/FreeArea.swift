import Geometry

/// The part of a display left for a layout once some windows have fixed places (per-app rules).
public enum FreeArea {
    /// The largest axis-aligned rectangle of `area` that overlaps none of `obstacles`, found greedily:
    /// for each obstacle in turn, keep the biggest of the strips left, right, above or below it.
    /// Returns `area` unchanged when nothing overlaps it.
    public static func largest(in area: Rect, avoiding obstacles: [Rect]) -> Rect {
        var free = area
        for o in obstacles where overlaps(o, free) {
            let candidates = [
                Rect(x: free.x, y: free.y, w: o.x - free.x, h: free.h),  // left of it
                Rect(x: o.x + o.w, y: free.y, w: free.x + free.w - (o.x + o.w), h: free.h),  // right
                Rect(x: free.x, y: free.y, w: free.w, h: o.y - free.y),  // above
                Rect(x: free.x, y: o.y + o.h, w: free.w, h: free.y + free.h - (o.y + o.h)),  // below
            ].filter { $0.w > 0 && $0.h > 0 }
            guard let best = candidates.max(by: { $0.w * $0.h < $1.w * $1.h }) else { return .zero }
            free = best
        }
        return free
    }

    static func overlaps(_ a: Rect, _ b: Rect) -> Bool {
        a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y
    }
}
