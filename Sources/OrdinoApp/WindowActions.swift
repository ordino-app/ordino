import AppKit
import Geometry
import LayoutEngine
import WindowKit

/// Runs single-window actions (halves, corners, thirds, maximize, displays...)
/// on the window the user is working in.
@MainActor
final class WindowActionController {
    enum Outcome {
        case done(WindowAction, appName: String)
        case noWindow
        case ignored(appName: String)
        case nothingToRestore
        case singleDisplay
        case notResizable(appName: String)
    }

    private let settings: Settings
    private let mover = WindowMover()
    /// Frame before ordino first touched a window, for Restore.
    private var originalFrames: [WindowID: Rect] = [:]
    /// The frame ordino last gave each window, to tell whether the user moved it since.
    private var lastApplied: [WindowID: Rect] = [:]
    private var lastAction: (window: WindowID, action: WindowAction, at: ContinuousClock.Instant, count: Int)?
    private let repeatInterval: Duration = .milliseconds(1500)

    init(settings: Settings) {
        self.settings = settings
    }

    /// - Parameters:
    ///   - onDisplayUnderMouse: place on the display under the cursor (drag-to-snap), not the window's display.
    ///   - originalFrame: the frame Restore goes back to, when the caller knows better than the current frame
    ///     (drag-to-snap passes the frame from before the drag).
    func perform(_ action: WindowAction, onDisplayUnderMouse: Bool = false, originalFrame: Rect? = nil) async -> Outcome
    {
        guard let window = WindowDiscovery.focusedWindow() else { return .noWindow }
        if let bundleID = window.bundleID, settings.ignoredApps.contains(bundleID) {
            return .ignored(appName: window.appName)
        }
        let id = window.info.id
        let current = window.info.frame

        // The user moved the window since ordino last placed it: that's the new "original".
        if let applied = lastApplied[id], !applied.isApproximately(current, tolerance: 2) {
            originalFrames[id] = nil
            lastApplied[id] = nil
        }

        let target: Rect
        switch action {
        case .restore:
            guard let original = originalFrames[id] else { return .nothingToRestore }
            target = original
            lastAction = nil
        case .nextDisplay, .previousDisplay:
            let displays = Displays.ordered()
            guard displays.count > 1, let from = Displays.containing(current),
                let index = displays.firstIndex(where: { $0.id == from.id })
            else { return .singleDisplay }
            let step = action == .nextDisplay ? 1 : -1
            let to = displays[(index + step + displays.count) % displays.count]
            target = settings.windowActionEngine.frame(
                movingWindow: current, from: from.visibleFrame, to: to.visibleFrame)
            lastAction = nil  // a half pressed next starts its cycle again on the new display
        default:
            if !window.info.isResizable, action == .larger || action == .smaller {
                return .notResizable(appName: window.appName)
            }
            guard let display = onDisplayUnderMouse ? Displays.underMouse() : Displays.containing(current)
            else { return .noWindow }
            let repeats = repeatCount(for: action, window: id, frame: current)
            guard
                let frame = settings.windowActionEngine.frame(
                    for: action, window: current, area: display.visibleFrame, repeatCount: repeats)
            else { return .noWindow }
            target = frame
        }

        if action != .restore, originalFrames[id] == nil { originalFrames[id] = originalFrame ?? current }
        let outcomes = await mover.apply([id: target], to: [window])
        var actual = outcomes.first?.actual ?? target

        if action == .larger || action == .smaller, actual.size == current.size {
            // The app refused the new size: don't let the window drift.
            _ = await mover.apply([id: current], to: [window])
            lastApplied[id] = current
            return .notResizable(appName: window.appName)
        }
        // An app with a minimum size can end up wider/taller than the target and
        // hang off the screen; pull it back inside the display.
        if let area = Displays.containing(actual)?.visibleFrame, !area.contains(actual, tolerance: 1) {
            var fixed = actual
            fixed.x = min(max(fixed.x, area.minX), max(area.minX, area.maxX - fixed.w))
            fixed.y = min(max(fixed.y, area.minY), max(area.minY, area.maxY - fixed.h))
            if fixed != actual {
                actual = (await mover.apply([id: fixed], to: [window])).first?.actual ?? fixed
            }
        }
        if action == .restore {
            originalFrames[id] = nil
            lastApplied[id] = nil
        } else {
            lastApplied[id] = actual
        }
        return .done(action, appName: window.appName)
    }

    /// The size a window had before ordino placed it, if `frame` is still where ordino put it
    /// (drag-to-snap restores it when a snapped window is dragged away).
    func originalFrameIfPlaced(_ id: WindowID, frame: Rect) -> Rect? {
        guard let applied = lastApplied[id], applied.isApproximately(frame, tolerance: 2) else { return nil }
        return originalFrames[id]
    }

    /// Forgets that ordino placed a window (it was dragged away and got its own size back).
    func forgetPlacement(_ id: WindowID) {
        originalFrames[id] = nil
        lastApplied[id] = nil
    }

    private func repeatCount(for action: WindowAction, window: WindowID, frame: Rect) -> Int {
        let now = ContinuousClock.now
        var count = 0
        if let last = lastAction, last.window == window, last.action == action, now - last.at <= repeatInterval,
            lastApplied[window].map({ $0.isApproximately(frame, tolerance: 2) }) ?? false
        {
            count = last.count + 1
        }
        lastAction = (window, action, now, count)
        return count
    }
}
