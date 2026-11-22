import Foundation
import Geometry

/// A single-window placement action (in the spirit of Rectangle).
public enum WindowAction: String, CaseIterable, Codable, Sendable, Identifiable {
    case leftHalf, rightHalf, centerHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case firstThird, centerThird, lastThird, firstTwoThirds, centerTwoThirds, lastTwoThirds
    case firstFourth, secondFourth, thirdFourth, lastFourth, firstThreeFourths, lastThreeFourths
    case topLeftSixth, topCenterSixth, topRightSixth, bottomLeftSixth, bottomCenterSixth, bottomRightSixth
    case maximize, almostMaximize, maximizeHeight, larger, smaller, center
    case moveLeft, moveRight, moveUp, moveDown
    case restore, nextDisplay, previousDisplay

    public var id: String { rawValue }

    /// Category used to group actions in menus and settings.
    public enum Group: String, CaseIterable, Sendable {
        case halves, corners, thirds, fourths, sixths, size, move, display
    }

    /// Human-readable name shown in menus and settings.
    public var title: String {
        switch self {
        case .leftHalf: "Left"
        case .rightHalf: "Right"
        case .centerHalf: "Center"
        case .topHalf: "Top"
        case .bottomHalf: "Bottom"
        case .topLeft: "Top Left"
        case .topRight: "Top Right"
        case .bottomLeft: "Bottom Left"
        case .bottomRight: "Bottom Right"
        case .firstThird: "First Third"
        case .centerThird: "Center Third"
        case .lastThird: "Last Third"
        case .firstTwoThirds: "First Two Thirds"
        case .centerTwoThirds: "Center Two Thirds"
        case .lastTwoThirds: "Last Two Thirds"
        case .firstFourth: "First Fourth"
        case .secondFourth: "Second Fourth"
        case .thirdFourth: "Third Fourth"
        case .lastFourth: "Last Fourth"
        case .firstThreeFourths: "First Three Fourths"
        case .lastThreeFourths: "Last Three Fourths"
        case .topLeftSixth: "Top Left Sixth"
        case .topCenterSixth: "Top Center Sixth"
        case .topRightSixth: "Top Right Sixth"
        case .bottomLeftSixth: "Bottom Left Sixth"
        case .bottomCenterSixth: "Bottom Center Sixth"
        case .bottomRightSixth: "Bottom Right Sixth"
        case .maximize: "Maximize"
        case .almostMaximize: "Almost Maximize"
        case .maximizeHeight: "Maximize Height"
        case .larger: "Larger"
        case .smaller: "Smaller"
        case .center: "Move to Center"
        case .moveLeft: "Move Left"
        case .moveRight: "Move Right"
        case .moveUp: "Move Up"
        case .moveDown: "Move Down"
        case .restore: "Restore"
        case .nextDisplay: "Next Display"
        case .previousDisplay: "Previous Display"
        }
    }

    public var group: Group {
        switch self {
        case .leftHalf, .rightHalf, .centerHalf, .topHalf, .bottomHalf: .halves
        case .topLeft, .topRight, .bottomLeft, .bottomRight: .corners
        case .firstThird, .centerThird, .lastThird, .firstTwoThirds, .centerTwoThirds, .lastTwoThirds: .thirds
        case .firstFourth, .secondFourth, .thirdFourth, .lastFourth, .firstThreeFourths, .lastThreeFourths:
            .fourths
        case .topLeftSixth, .topCenterSixth, .topRightSixth, .bottomLeftSixth, .bottomCenterSixth,
            .bottomRightSixth:
            .sixths
        case .maximize, .almostMaximize, .maximizeHeight, .larger, .smaller: .size
        case .center, .moveLeft, .moveRight, .moveUp, .moveDown: .move
        case .restore, .nextDisplay, .previousDisplay: .display
        }
    }

    /// For icons: the unit-square rectangle (0...1, top-left origin) this action produces, or nil for
    /// actions without a fixed region (larger, smaller, center, move*, restore, *Display).
    public var unitRect: Rect? {
        switch self {
        case .almostMaximize: return Rect(x: 0.05, y: 0.05, w: 0.9, h: 0.9)
        case .maximizeHeight: return Rect(x: 0.25, y: 0, w: 0.5, h: 1)
        default:
            guard let s = span(repeatCount: 0) else { return nil }
            return Rect(x: s.x0, y: s.y0, w: s.x1 - s.x0, h: s.y1 - s.y0)
        }
    }

    /// Fractional region `[x0, x1] x [y0, y1]` of the usable area for tiling actions.
    func span(repeatCount: Int) -> Span? {
        let cycle: [Double] = [1.0 / 2, 2.0 / 3, 1.0 / 3]
        let f = cycle[((repeatCount % cycle.count) + cycle.count) % cycle.count]
        let third = 1.0 / 3
        switch self {
        case .leftHalf: return Span(0, f, 0, 1)
        case .rightHalf: return Span(1 - f, 1, 0, 1)
        case .centerHalf: return Span(0.25, 0.75, 0, 1)
        case .topHalf: return Span(0, 1, 0, f)
        case .bottomHalf: return Span(0, 1, 1 - f, 1)
        case .topLeft: return Span(0, 0.5, 0, 0.5)
        case .topRight: return Span(0.5, 1, 0, 0.5)
        case .bottomLeft: return Span(0, 0.5, 0.5, 1)
        case .bottomRight: return Span(0.5, 1, 0.5, 1)
        case .firstThird: return Span(0, third, 0, 1)
        case .centerThird: return Span(third, 2 * third, 0, 1)
        case .lastThird: return Span(2 * third, 1, 0, 1)
        case .firstTwoThirds: return Span(0, 2 * third, 0, 1)
        case .centerTwoThirds: return Span(third / 2, 1 - third / 2, 0, 1)
        case .lastTwoThirds: return Span(third, 1, 0, 1)
        case .firstFourth: return Span(0, 0.25, 0, 1)
        case .secondFourth: return Span(0.25, 0.5, 0, 1)
        case .thirdFourth: return Span(0.5, 0.75, 0, 1)
        case .lastFourth: return Span(0.75, 1, 0, 1)
        case .firstThreeFourths: return Span(0, 0.75, 0, 1)
        case .lastThreeFourths: return Span(0.25, 1, 0, 1)
        case .topLeftSixth: return Span(0, third, 0, 0.5)
        case .topCenterSixth: return Span(third, 2 * third, 0, 0.5)
        case .topRightSixth: return Span(2 * third, 1, 0, 0.5)
        case .bottomLeftSixth: return Span(0, third, 0.5, 1)
        case .bottomCenterSixth: return Span(third, 2 * third, 0.5, 1)
        case .bottomRightSixth: return Span(2 * third, 1, 0.5, 1)
        case .maximize: return Span(0, 1, 0, 1)
        default: return nil
        }
    }

    struct Span: Sendable {
        var x0: Double
        var x1: Double
        var y0: Double
        var y1: Double

        init(_ x0: Double, _ x1: Double, _ y0: Double, _ y1: Double) {
            self.x0 = x0
            self.x1 = x1
            self.y0 = y0
            self.y1 = y1
        }
    }
}

/// Pure calculator of target frames for ``WindowAction``s on a single display.
public struct WindowActionEngine: Sendable {
    /// Space between windows placed side by side (applied as gap/2 on inner edges).
    public var gap: Double
    /// Inset of the usable area.
    public var outerPadding: Insets
    /// Larger/smaller step in points, applied on each side.
    public var sizeStep: Double
    /// Fraction of each dimension used by `.almostMaximize`.
    public var almostMaximizeFraction: Double
    /// `.smaller` never shrinks a window below this size.
    public var minimumSize: Size

    public init(
        gap: Double = 0, outerPadding: Insets = .zero, sizeStep: Double = 32, almostMaximizeFraction: Double = 0.9,
        minimumSize: Size = Size(w: 320, h: 220)
    ) {
        self.gap = gap
        self.outerPadding = outerPadding
        self.sizeStep = sizeStep
        self.almostMaximizeFraction = almostMaximizeFraction
        self.minimumSize = minimumSize
    }

    /// Target frame for an action on one display. Returns nil for .restore, .nextDisplay, .previousDisplay
    /// (the caller handles those).
    /// - Parameter repeatCount: how many times in a row the same action was just applied (0 = first press).
    ///   Halves cycle on repeat: 1/2 -> 2/3 -> 1/3 -> 1/2... Other actions ignore it.
    public func frame(for action: WindowAction, window: Rect, area: Rect, repeatCount: Int = 0) -> Rect? {
        let a = area.inset(by: outerPadding)
        if let s = action.span(repeatCount: repeatCount) {
            return place(s, in: a)
        }
        switch action {
        case .almostMaximize:
            let f = min(1, max(0, almostMaximizeFraction))
            return a.centered(size: Size(w: a.w * f, h: a.h * f), clampedTo: a)
        case .maximizeHeight:
            let w = min(window.w, a.w)
            let x = clamp(window.x, a.minX, a.maxX - w)
            return Rect(x: x, y: a.y, w: w, h: a.h)
        case .center:
            return a.centered(size: Size(w: min(window.w, a.w), h: min(window.h, a.h)), clampedTo: a)
        case .larger:
            let size = Size(w: min(window.w + 2 * sizeStep, a.w), h: min(window.h + 2 * sizeStep, a.h))
            return window.centered(size: size, clampedTo: a)
        case .smaller:
            let w = max(window.w - 2 * sizeStep, min(minimumSize.w, window.w))
            let h = max(window.h - 2 * sizeStep, min(minimumSize.h, window.h))
            return window.centered(size: Size(w: min(w, a.w), h: min(h, a.h)), clampedTo: a)
        case .moveLeft, .moveRight, .moveUp, .moveDown:
            var r = clamped(window, to: a)
            switch action {
            case .moveLeft: r.x = a.minX
            case .moveRight: r.x = a.maxX - r.w
            case .moveUp: r.y = a.minY
            default: r.y = a.maxY - r.h
            }
            return r
        default:
            return nil
        }
    }

    /// Maps a window from one display's usable area to another's, keeping its relative position and size;
    /// a window filling (>=95%) the old area fills the new one; result clamped inside the new area.
    /// Both areas have `outerPadding` applied.
    public func frame(movingWindow window: Rect, from source: Rect, to target: Rect) -> Rect {
        let s = source.inset(by: outerPadding)
        let t = target.inset(by: outerPadding)
        guard s.w > 0, s.h > 0 else { return clamped(window, to: t) }
        if window.w >= s.w * 0.95, window.h >= s.h * 0.95 { return t }
        let sx = t.w / s.w
        let sy = t.h / s.h
        let mapped = Rect(
            x: t.x + (window.x - s.x) * sx,
            y: t.y + (window.y - s.y) * sy,
            w: window.w * sx,
            h: window.h * sy)
        return clamped(mapped, to: t)
    }

    // MARK: - Helpers

    private func place(_ s: WindowAction.Span, in a: Rect) -> Rect {
        let half = gap / 2
        var x0 = a.x + s.x0 * a.w
        var x1 = a.x + s.x1 * a.w
        var y0 = a.y + s.y0 * a.h
        var y1 = a.y + s.y1 * a.h
        if s.x0 > 0 { x0 += half }
        if s.x1 < 1 { x1 -= half }
        if s.y0 > 0 { y0 += half }
        if s.y1 < 1 { y1 -= half }
        return Rect(x: x0, y: y0, w: max(0, x1 - x0), h: max(0, y1 - y0))
    }

    private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        min(max(v, lo), max(lo, hi))
    }

    private func clamped(_ r: Rect, to a: Rect) -> Rect {
        let w = min(r.w, a.w)
        let h = min(r.h, a.h)
        return Rect(x: clamp(r.x, a.minX, a.maxX - w), y: clamp(r.y, a.minY, a.maxY - h), w: w, h: h)
    }
}

extension WindowAction {
    /// Placements that make sense as a standing per-app rule.
    public static let ruleChoices: [WindowAction] = [
        .leftHalf, .rightHalf, .topHalf, .bottomHalf,
        .topLeft, .topRight, .bottomLeft, .bottomRight,
        .firstThird, .centerThird, .lastThird, .maximize, .almostMaximize, .center,
    ]
}
