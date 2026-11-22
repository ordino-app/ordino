import AppKit
import Geometry
import LayoutEngine
import WindowKit

/// Drag a window to a screen edge to snap it (like Windows): left/right edge = half,
/// top edge = maximize, corners = quarters. A translucent preview shows the target while
/// dragging; releasing the mouse there applies the window action. Hold ⌘ to drag freely.
@MainActor
final class DragSnapController {
    private let settings: Settings
    private let perform: (WindowAction) -> Void
    private var monitor: Any?
    private var drag: (windowID: WindowID, origin: Rect, bundleID: String?)?
    private var isMoving = false
    /// Drag events checked without the window moving; after a few, it's not a window move (text selection,
    /// file drag, resize) and the AX reads stop for this drag.
    private var misses = 0
    private var target: WindowAction?
    private lazy var preview = SnapPreviewPanel()

    /// How close to an edge (points) the cursor must be; corners take this much along each edge.
    private let edge: Double = 6
    private let corner: Double = 48

    init(settings: Settings, perform: @escaping (WindowAction) -> Void) {
        self.settings = settings
        self.perform = perform
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) {
            [weak self] event in
            let type = event.type
            let flags = event.modifierFlags
            MainActor.assumeIsolated { self?.handle(type, flags: flags) }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        reset()
    }

    private func handle(_ type: NSEvent.EventType, flags: NSEvent.ModifierFlags) {
        switch type {
        case .leftMouseDown:
            reset()
            guard settings.snapOnDrag, AccessibilityPermission.isTrusted,
                let window = WindowDiscovery.focusedWindow()
            else { return }
            drag = (window.info.id, window.info.frame, window.bundleID)
        case .leftMouseDragged:
            guard let d = drag, settings.snapOnDrag, !flags.contains(.command) else { return hidePreview() }
            if let b = d.bundleID, settings.ignoredApps.contains(b) { return }
            if !isMoving {
                // Only window moves snap (not resizing, selecting text or dragging files): the focused
                // window's origin has to change while its size stays the same.
                guard let now = WindowDiscovery.focusedWindow(), now.info.id == d.windowID else { return giveUp() }
                let f = now.info.frame
                let moved = abs(f.x - d.origin.x) > 2 || abs(f.y - d.origin.y) > 2
                let sameSize = abs(f.w - d.origin.w) < 2 && abs(f.h - d.origin.h) < 2
                guard sameSize else { return giveUp(now: true) }
                guard moved else { return giveUp() }
                isMoving = true
            }
            updateTarget()
        case .leftMouseUp:
            let action = target
            let moving = isMoving
            reset()
            if moving, let action { perform(action) }
        default:
            break
        }
    }

    /// Picks the snap zone under the cursor and shows its preview.
    private func updateTarget() {
        let (px, py) = Self.mouseInQuartz()
        guard let display = Displays.all().first(where: { $0.frame.contains(pointX: px, y: py) }) else {
            return hidePreview()
        }
        guard let action = SnapZone.action(x: px, y: py, in: display.frame, edge: edge, corner: corner),
            let frame = settings.windowActionEngine.frame(
                for: action, window: drag?.origin ?? .zero, area: display.visibleFrame)
        else { return hidePreview() }
        target = action
        preview.show(quartzFrame: frame)
    }

    /// Stops checking this drag after a handful of non-moving events, or at once when the window is resizing.
    private func giveUp(now: Bool = false) {
        misses += 1
        if now || misses > 6 { drag = nil }
    }

    private func hidePreview() {
        target = nil
        preview.orderOut(nil)
    }

    private func reset() {
        drag = nil
        isMoving = false
        misses = 0
        hidePreview()
    }

    /// The cursor in Quartz global coordinates (origin top-left of the primary display), like window frames.
    static func mouseInQuartz() -> (Double, Double) {
        let m = NSEvent.mouseLocation
        return (Double(m.x), SnapPreviewPanel.primaryHeight - Double(m.y))
    }
}

/// The translucent rounded rectangle that shows where the window will snap.
@MainActor
final class SnapPreviewPanel: NSPanel {
    static var primaryHeight: Double {
        let primary = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first
        return Double(primary?.frame.height ?? 0)
    }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        let box = NSVisualEffectView()
        box.material = .hudWindow
        box.state = .active
        box.wantsLayer = true
        box.layer?.cornerRadius = 12
        box.layer?.borderWidth = 2
        box.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.7).cgColor
        box.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
        contentView = box
    }

    func show(quartzFrame r: Rect) {
        let frame = NSRect(x: r.x, y: Self.primaryHeight - r.y - r.h, width: r.w, height: r.h).insetBy(dx: 4, dy: 4)
        if !isVisible || self.frame != frame {
            setFrame(frame, display: true)
            orderFrontRegardless()
        }
    }
}
