import AppKit
import ApplicationServices
import Geometry
import LayoutEngine

/// A window found on screen, with a live AX handle for moving it.
@MainActor
public final class DiscoveredWindow {
    public let info: WindowInfo
    public let pid: pid_t
    public let appName: String
    public let bundleID: String?
    /// Window title via AX (no Screen Recording permission needed). Local only.
    public let title: String
    /// z-order index, 0 = frontmost.
    public let zIndex: Int
    let element: AXUIElement
    let appElement: AXUIElement

    init(
        info: WindowInfo, pid: pid_t, appName: String, bundleID: String?, title: String,
        zIndex: Int, element: AXUIElement, appElement: AXUIElement
    ) {
        self.info = info
        self.pid = pid
        self.appName = appName
        self.bundleID = bundleID
        self.title = title
        self.zIndex = zIndex
        self.element = element
        self.appElement = appElement
    }
}

/// Why a window was skipped (shown in diagnostics and the UI).
public struct SkippedWindow: Sendable, CustomStringConvertible {
    public let id: UInt32
    public let appName: String
    public let reason: String
    public var description: String { "#\(id) \(appName): \(reason)" }
}

@MainActor
public struct WindowDiscovery {
    /// Windows smaller than this are ignored (palettes, toasts, widgets).
    public var minimumWindowSize = Size(w: 160, h: 100)
    /// Per-app AX timeout so one hung app can't stall arranging.
    public var messagingTimeout: Float = 0.25
    /// Bundle IDs that are never touched.
    public var excludedBundleIDs: Set<String> = []

    public init() {}

    public struct Result {
        public let windows: [DiscoveredWindow]  // z-order, frontmost first
        public let skipped: [SkippedWindow]
    }

    /// The focused window of the app the user is working in. When ordino itself
    /// is frontmost (onboarding, relaunch from Finder), the last other app that
    /// was active is used instead (see ``FrontmostAppTracker``).
    public static func focusedWindowID() -> UInt32? {
        let own = ProcessInfo.processInfo.processIdentifier
        var pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if pid == nil || pid == own { pid = FrontmostAppTracker.shared.lastExternalPID }
        guard let pid, pid != own else { return nil }
        let el = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(el, 0.25)
        guard let window = el.element(AXAttr.focusedWindow) else { return nil }
        AXUIElementSetMessagingTimeout(window, 0.25)
        return window.windowID
    }

    /// The window the user is working in (frontmost app's focused window, or the
    /// last other app's when ordino itself is frontmost), ready to be moved.
    public static func focusedWindow(messagingTimeout: Float = 0.25) -> DiscoveredWindow? {
        let own = ProcessInfo.processInfo.processIdentifier
        var pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if pid == nil || pid == own { pid = FrontmostAppTracker.shared.lastExternalPID }
        guard let pid, pid != own else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        guard let window = app.element(AXAttr.focusedWindow) else { return nil }
        AXUIElementSetMessagingTimeout(window, messagingTimeout)
        guard let id = window.windowID,
            let position = window.point(AXAttr.position), let size = window.size(AXAttr.size),
            window.bool(AXAttr.fullScreen) != true
        else { return nil }
        let running = NSRunningApplication(processIdentifier: pid)
        let info = WindowInfo(
            id: id, frame: Rect(x: position.x, y: position.y, w: size.width, h: size.height),
            isResizable: window.isSettable(AXAttr.size), isFocused: true)
        return DiscoveredWindow(
            info: info, pid: pid, appName: running?.localizedName ?? "App", bundleID: running?.bundleIdentifier,
            title: window.string(AXAttr.title) ?? "", zIndex: 0, element: window, appElement: app)
    }

    public func windows(on display: DisplayInfo, focusedID: UInt32? = Self.focusedWindowID()) -> Result {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let list = (CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]) ?? []

        struct CGEntry {
            let id: CGWindowID
            let pid: pid_t
            let owner: String
            let bounds: Rect
            let z: Int
        }
        var entries: [CGEntry] = []
        for (z, item) in list.enumerated() {
            guard (item["kCGWindowLayer"] as? Int) == 0,
                let id = item["kCGWindowNumber"] as? CGWindowID,
                let pid = item["kCGWindowOwnerPID"] as? pid_t, pid != ownPID,
                let dict = item["kCGWindowBounds"] as? NSDictionary,
                let cg = CGRect(dictionaryRepresentation: dict as CFDictionary)
            else { continue }
            if let alpha = item["kCGWindowAlpha"] as? Double, alpha <= 0.01 { continue }
            entries.append(
                CGEntry(
                    id: id, pid: pid, owner: item["kCGWindowOwnerName"] as? String ?? "?",
                    bounds: Rect(cg), z: z))
        }

        var skipped: [SkippedWindow] = []
        // A window belongs to the display it overlaps most (not just where its
        // centre is), so half-off-screen windows on offset monitors still count.
        let allDisplays = Displays.all()
        func owner(of r: Rect) -> DisplayInfo? {
            allDisplays.max { ($0.frame.intersection(r)?.area ?? 0) < ($1.frame.intersection(r)?.area ?? 0) }
                .flatMap { ($0.frame.intersection(r)?.area ?? 0) > 0 ? $0 : nil }
        }
        let onDisplay = entries.filter { e in
            guard let d = owner(of: e.bounds) else {
                skipped.append(SkippedWindow(id: e.id, appName: e.owner, reason: "off screen"))
                return false
            }
            return d.id == display.id
        }

        // Resolve AX elements once per app.
        var axByPID: [pid_t: (app: AXUIElement, windows: [CGWindowID: AXUIElement])] = [:]
        for pid in Set(onDisplay.map(\.pid)) {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, messagingTimeout)
            var map: [CGWindowID: AXUIElement] = [:]
            for w in app.elements(AXAttr.windows) {
                // Each element has its own timeout; the app's doesn't carry over.
                AXUIElementSetMessagingTimeout(w, messagingTimeout)
                if let id = w.windowID { map[id] = w }
            }
            axByPID[pid] = (app, map)
        }

        var result: [DiscoveredWindow] = []
        for e in onDisplay {
            let running = NSRunningApplication(processIdentifier: e.pid)
            let bundleID = running?.bundleIdentifier
            let name = running?.localizedName ?? e.owner
            func skip(_ reason: String) { skipped.append(SkippedWindow(id: e.id, appName: name, reason: reason)) }

            if let b = bundleID, excludedBundleIDs.contains(b) {
                skip("excluded")
                continue
            }
            if e.bounds.w < minimumWindowSize.w || e.bounds.h < minimumWindowSize.h {
                skip("too small")
                continue
            }
            guard let ax = axByPID[e.pid], let el = ax.windows[e.id] else {
                skip("no AX element (permission? other Space?)")
                continue
            }
            if el.string(AXAttr.subrole) != AXAttr.standardWindow {
                skip("not a standard window (\(el.string(AXAttr.subrole) ?? "nil"))")
                continue
            }
            if el.bool(AXAttr.minimized) == true {
                skip("minimized")
                continue
            }
            if el.bool(AXAttr.fullScreen) == true {
                skip("full screen")
                continue
            }

            let info = WindowInfo(
                id: e.id, frame: e.bounds, minSize: nil,
                isResizable: el.isSettable(AXAttr.size),
                isFocused: e.id == focusedID)
            result.append(
                DiscoveredWindow(
                    info: info, pid: e.pid, appName: name, bundleID: bundleID,
                    title: el.string(AXAttr.title) ?? "", zIndex: e.z,
                    element: el, appElement: ax.app))
        }
        return Result(windows: result, skipped: skipped)
    }
}
