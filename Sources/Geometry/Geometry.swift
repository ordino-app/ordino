import Foundation

/// A 2-D size in points.
public struct Size: Sendable, Hashable, Codable {
    public var w: Double
    public var h: Double

    public init(w: Double, h: Double) {
        self.w = w
        self.h = h
    }

    public static let zero = Size(w: 0, h: 0)
}

/// Edge insets in points.
public struct Insets: Sendable, Hashable, Codable {
    public var top: Double
    public var left: Double
    public var bottom: Double
    public var right: Double

    public init(top: Double, left: Double, bottom: Double, right: Double) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    public init(all value: Double) {
        self.init(top: value, left: value, bottom: value, right: value)
    }

    public static let zero = Insets(all: 0)
}

/// Split direction of a container.
/// `.horizontal` lays children out side by side (along x);
/// `.vertical` stacks them (along y).
public enum Axis: Sendable, Hashable, Codable {
    case horizontal
    case vertical

    public var flipped: Axis { self == .horizontal ? .vertical : .horizontal }
}

/// An axis-aligned rectangle.
///
/// ordino works in **Quartz global coordinates** (origin at the top-left of the
/// primary display, y grows downward), which is what the Accessibility API and
/// `CGWindowListCopyWindowInfo` use. Convert from AppKit (`NSScreen`) with
/// ``Rect/flippedVertically(primaryHeight:)``.
public struct Rect: Sendable, Hashable, Codable, CustomStringConvertible {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    public static let zero = Rect(x: 0, y: 0, w: 0, h: 0)

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + w }
    public var maxY: Double { y + h }
    public var midX: Double { x + w / 2 }
    public var midY: Double { y + h / 2 }
    public var size: Size { Size(w: w, h: h) }
    public var area: Double { max(0, w) * max(0, h) }
    public var diagonal: Double { (w * w + h * h).squareRoot() }

    /// Width divided by height, or 0 for a degenerate rect.
    public var aspect: Double { h > 0 ? w / h : 0 }

    /// Length along an axis (`.horizontal` -> width).
    public func length(along axis: Axis) -> Double { axis == .horizontal ? w : h }

    public func inset(by i: Insets) -> Rect {
        Rect(
            x: x + i.left,
            y: y + i.top,
            w: max(0, w - i.left - i.right),
            h: max(0, h - i.top - i.bottom))
    }

    public func intersection(_ other: Rect) -> Rect? {
        let x0 = max(minX, other.minX)
        let y0 = max(minY, other.minY)
        let x1 = min(maxX, other.maxX)
        let y1 = min(maxY, other.maxY)
        guard x1 > x0, y1 > y0 else { return nil }
        return Rect(x: x0, y: y0, w: x1 - x0, h: y1 - y0)
    }

    /// True if the two rects share more than `tolerance` square points of area.
    public func overlaps(_ other: Rect, tolerance: Double = 0.5) -> Bool {
        (intersection(other)?.area ?? 0) > tolerance
    }

    public func contains(_ other: Rect, tolerance: Double = 0.5) -> Bool {
        other.minX >= minX - tolerance && other.minY >= minY - tolerance && other.maxX <= maxX + tolerance
            && other.maxY <= maxY + tolerance
    }

    public func contains(pointX px: Double, y py: Double) -> Bool {
        px >= minX && px < maxX && py >= minY && py < maxY
    }

    /// Converts between AppKit's bottom-left-origin space and Quartz's
    /// top-left-origin space. The transform is its own inverse.
    /// - Parameter primaryHeight: height of the primary display (the one whose
    ///   AppKit frame origin is `(0, 0)`).
    public func flippedVertically(primaryHeight: Double) -> Rect {
        Rect(x: x, y: primaryHeight - y - h, w: w, h: h)
    }

    /// A rect of `size` centered in `self`, shifted so it stays inside `bounds`
    /// where possible.
    public func centered(size s: Size, clampedTo bounds: Rect) -> Rect {
        var r = Rect(x: midX - s.w / 2, y: midY - s.h / 2, w: s.w, h: s.h)
        r.x = min(max(r.x, bounds.minX), max(bounds.minX, bounds.maxX - r.w))
        r.y = min(max(r.y, bounds.minY), max(bounds.minY, bounds.maxY - r.h))
        return r
    }

    /// Component-wise equality within a tolerance.
    public func isApproximately(_ other: Rect, tolerance: Double = 1) -> Bool {
        abs(x - other.x) <= tolerance && abs(y - other.y) <= tolerance && abs(w - other.w) <= tolerance
            && abs(h - other.h) <= tolerance
    }

    public var description: String {
        func f(_ v: Double) -> String { String(format: "%.0f", v) }
        return "(\(f(x)), \(f(y)) \(f(w))x\(f(h)))"
    }
}
