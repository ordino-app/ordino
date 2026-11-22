import Geometry

/// A user-defined grid (e.g. 3 columns for an ultrawide display): equal cells, row by row.
public enum GridLayout {
    /// Cell frames of a `columns` x `rows` grid filling `area`, left to right then top to bottom,
    /// with `gap` points between cells.
    public static func frames(in area: Rect, columns: Int, rows: Int, gap: Double = 0) -> [Rect] {
        let c = max(1, columns)
        let r = max(1, rows)
        let w = (area.w - gap * Double(c - 1)) / Double(c)
        let h = (area.h - gap * Double(r - 1)) / Double(r)
        return (0..<r).flatMap { row in
            (0..<c).map { col in
                Rect(x: area.x + Double(col) * (w + gap), y: area.y + Double(row) * (h + gap), w: w, h: h)
            }
        }
    }
}
