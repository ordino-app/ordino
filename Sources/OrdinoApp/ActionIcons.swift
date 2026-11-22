import AppKit
import Geometry
import LayoutEngine

/// Small template icons for menus and the Settings window: a rounded screen
/// outline with the area an action produces filled in (like Rectangle's menu).
@MainActor
enum ActionIcons {
    private static var cache: [String: NSImage] = [:]

    static func image(for action: WindowAction) -> NSImage {
        if let unit = action.unitRect { return region(unit, key: action.rawValue) }
        let symbol: String =
            switch action {
            case .larger: "plus.rectangle"
            case .smaller: "minus.rectangle"
            case .center: "rectangle.center.inset.filled"
            case .moveLeft: "arrow.left.to.line"
            case .moveRight: "arrow.right.to.line"
            case .moveUp: "arrow.up.to.line"
            case .moveDown: "arrow.down.to.line"
            case .restore: "arrow.uturn.backward"
            case .nextDisplay: "arrow.right.square"
            case .previousDisplay: "arrow.left.square"
            default: "rectangle"
            }
        return NSImage(systemSymbolName: symbol, accessibilityDescription: action.title) ?? NSImage()
    }

    /// Icon for an arrange layout, drawn from the engine's real slot geometry.
    static func image(for layout: LayoutID, windowCount: Int) -> NSImage {
        let key = "layout-\(layout.rawValue)-\(windowCount)"
        if let cached = cache[key] { return cached }
        var prefs = LayoutPreferences()
        prefs.gap = 0.07
        prefs.outerPadding = .zero
        let area = Rect(x: 0, y: 0, w: 1.6, h: 1)
        let windows = (0..<max(1, windowCount)).map { WindowInfo(id: WindowID($0 + 1), frame: area) }
        let plan = LayoutEngine().plan(LayoutContext(area: area, windows: windows, preferences: prefs), layout: layout)
        let rects = (plan?.frames.values).map { Array($0) } ?? []
        let image = draw(key: key) { box in
            for r in rects {
                let unit = Rect(x: r.x / area.w, y: r.y / area.h, w: r.w / area.w, h: r.h / area.h)
                NSBezierPath(roundedRect: box(unit), xRadius: 0.8, yRadius: 0.8).fill()
            }
        }
        return image
    }

    private static func region(_ unit: Rect, key: String) -> NSImage {
        draw(key: key) { box in
            NSBezierPath(roundedRect: box(unit), xRadius: 0.8, yRadius: 0.8).fill()
        }
    }

    /// 20x14 pt template image: outline of a screen, content drawn by `body`
    /// with a helper that maps unit rects (top-left origin) into the screen.
    private static func draw(key: String, body: @escaping (_ box: (Rect) -> NSRect) -> Void) -> NSImage {
        if let cached = cache[key] { return cached }
        let size = NSSize(width: 20, height: 14)
        let image = NSImage(size: size, flipped: true) { _ in
            let outer = NSRect(x: 1, y: 1.5, width: 18, height: 11)
            NSColor.black.setStroke()
            let frame = NSBezierPath(roundedRect: outer, xRadius: 2, yRadius: 2)
            frame.lineWidth = 1.2
            frame.stroke()
            let inner = outer.insetBy(dx: 2, dy: 2)
            NSColor.black.setFill()
            body { u in
                NSRect(
                    x: inner.minX + u.x * inner.width, y: inner.minY + u.y * inner.height,
                    width: u.w * inner.width, height: u.h * inner.height)
            }
            return true
        }
        image.isTemplate = true
        cache[key] = image
        return image
    }
}
