import AppKit
import Geometry
import LayoutEngine
import WindowKit

/// Drag a window to a screen edge to snap it (like Windows): left/right edge = half, top edge = maximize,
/// the very corners = quarters. A translucent preview shows the target while dragging; releasing the mouse
/// there places the window on the display under the cursor. Hold ⌘ to drag freely. Dragging a window that
/// ordino placed gives it its earlier size back, so it doesn't stay a huge half while you move it.
@MainActor
final class DragSnapController {
    private let settings: Settings
    private let windowActions: WindowActionController
    private let onSnapped: (WindowActionController.Outcome) -> Void
    private var monitor: Any?

    /// A left-button drag that may still turn out to be a window move.
    private var tracking = false
    private var isMoving = false
    /// The dragged window and its frame when the drag started.
    private var drag: (window: DiscoveredWindow, origin: Rect)?
    /// Frame Restore should return to after this snap: the window's frame from before the drag.
    private var restoreFrame: Rect?
    private var dragStart: ContinuousClock.Instant?
    private var lastCheck: ContinuousClock.Instant?
    private var target: WindowAction?
    private lazy var preview = SnapPreviewPanel()
    private let mover = WindowMover()

    init(
        settings: Settings, windowActions: WindowActionController,
        onSnapped: @escaping (WindowActionController.Outcome) -> Void
    ) {
        self.settings = settings
        self.windowActions = windowActions
        self.onSnapped = onSnapped
    }

    /// macOS 15+ has its own drag-to-edge tiling (System Settings › Desktop & Dock). When it's on, both would
    /// act on the same drag, so ordino stays out of the way. A missing key means the system default: on.
    static var systemTilingEnabled: Bool {
        let d = UserDefaults(suiteName: "com.apple.WindowManager")
        let edges = d?.object(forKey: "EnableTilingByEdgeDrag") as? Bool ?? true
        let top = d?.object(forKey: "EnableTopTilingByEdgeDrag") as? Bool ?? true
        return edges || top
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
            tracking = settings.snapOnDrag && AccessibilityPermission.isTrusted && !Self.systemTilingEnabled
        case .leftMouseDragged:
            guard tracking else { return }
            if !isMoving { detectMove() }
            guard isMoving else { return }
            if flags.contains(.command) { return hidePreview() }
            updateTarget()
        case .leftMouseUp:
            let action = target
            let moving = isMoving
            let original = restoreFrame
            reset()
            guard moving, let action else { return }
            log("snap \(action.rawValue)")
            // Let macOS finish its own window drag first, or it can put the window back.
            Task { @MainActor [windowActions, onSnapped] in
                try? await Task.sleep(for: .milliseconds(80))
                let outcome = await windowActions.perform(action, onDisplayUnderMouse: true, originalFrame: original)
                onSnapped(outcome)
            }
        default:
            break
        }
    }

    /// Decides whether this drag moves a window. The click focuses the window first, so it's read on the drag,
    /// not on mouse-down. A move changes the focused window's origin but not its size (a resize, a text
    /// selection or a file drag doesn't). Reads are throttled, and after 0.6 s without the window moving the
    /// drag is ignored.
    private func detectMove() {
        let now = ContinuousClock.now
        if dragStart == nil { dragStart = now }
        if let last = lastCheck, now - last < .milliseconds(30) { return }
        lastCheck = now
        if let start = dragStart, now - start > .milliseconds(600) {
            tracking = false
            return
        }
        guard let window = WindowDiscovery.focusedWindow() else { return }
        if let b = window.bundleID, settings.ignoredApps.contains(b) {
            tracking = false
            return
        }
        guard let d = drag, d.window.info.id == window.info.id else {
            drag = (window, window.info.frame)
            return
        }
        let f = window.info.frame
        let moved = abs(f.x - d.origin.x) > 1 || abs(f.y - d.origin.y) > 1
        let sameSize = abs(f.w - d.origin.w) < 2 && abs(f.h - d.origin.h) < 2
        guard sameSize else {
            tracking = false  // resizing
            return
        }
        guard moved else { return }
        isMoving = true
        restoreFrame = d.origin
        log("move \(window.appName)")
        unsnapIfPlaced(window, startFrame: d.origin)
    }

    /// A window ordino placed (snapped, halved...) gets its earlier size back as soon as it's dragged away,
    /// centred horizontally under the cursor, like on Windows.
    private func unsnapIfPlaced(_ window: DiscoveredWindow, startFrame: Rect) {
        guard let original = windowActions.originalFrameIfPlaced(window.info.id, frame: startFrame),
            original.w < startFrame.w - 2 || original.h < startFrame.h - 2
        else { return }
        let (px, _) = Self.mouseInQuartz()
        let current = WindowDiscovery.focusedWindow()?.info.frame ?? startFrame
        let frame = Rect(x: px - original.w / 2, y: current.y, w: original.w, h: original.h)
        windowActions.forgetPlacement(window.info.id)
        restoreFrame = original
        log("unsnap to \(Int(original.w))x\(Int(original.h))")
        Task { [mover] in _ = await mover.apply([window.info.id: frame], to: [window]) }
    }

    /// Picks the snap zone under the cursor and shows its preview.
    private func updateTarget() {
        let (px, py) = Self.mouseInQuartz()
        let displays = Displays.all()
        guard let display = displays.first(where: { $0.frame.contains(pointX: px, y: py) }),
            let action = SnapZone.action(
                x: px, y: py, in: display.frame, others: displays.filter { $0.id != display.id }.map(\.frame)),
            let frame = settings.windowActionEngine.frame(
                for: action, window: drag?.origin ?? .zero, area: display.visibleFrame)
        else { return hidePreview() }
        target = action
        preview.show(quartzFrame: frame)
    }

    private func hidePreview() {
        target = nil
        preview.orderOut(nil)
    }

    private func reset() {
        tracking = false
        isMoving = false
        drag = nil
        restoreFrame = nil
        dragStart = nil
        lastCheck = nil
        hidePreview()
    }

    /// The cursor in Quartz global coordinates (origin top-left of the primary display), like window frames.
    static func mouseInQuartz() -> (Double, Double) {
        let m = NSEvent.mouseLocation
        return (Double(m.x), SnapPreviewPanel.primaryHeight - Double(m.y))
    }

    /// Debug builds append to ~/Library/Logs/ordino-snap.log, to diagnose drags without a debugger.
    private func log(_ message: @autoclosure () -> String) {
        #if DEBUG
            let line = "\(Date()) \(message())\n"
            let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Logs/ordino-snap.log")
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile()
                h.write(Data(line.utf8))
                try? h.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        #endif
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
        guard !isVisible || self.frame != frame else { return }
        setFrame(frame, display: true)
        orderFrontRegardless()
    }
}
