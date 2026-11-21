import AppKit
import ApplicationServices
import Geometry
import LayoutEngine

/// Applies target frames through the AX API and reports what really happened.
@MainActor
public struct WindowMover {
    /// Time to let asynchronous apps (Electron, JetBrains) settle before reading back.
    public var settleDelay: Duration = .milliseconds(60)

    public init() {}

    public struct Outcome: CustomStringConvertible {
        public let id: WindowID
        public let target: Rect
        public let actual: Rect?
        public let error: AXError?
        public var matched: Bool { actual.map { $0.isApproximately(target, tolerance: 2) } ?? false }
        public var description: String {
            let a = actual.map(\.description) ?? "?"
            return "#\(id) target \(target) actual \(a)" + (matched ? "" : "  <-- mismatch")
                + (error.map { " err=\($0.rawValue)" } ?? "")
        }
    }

    /// Moves every window to its target. Returns per-window outcomes after a settle delay.
    public func apply(_ frames: [WindowID: Rect], to windows: [DiscoveredWindow]) async -> [Outcome] {
        let voiceOverOn = NSWorkspace.shared.isVoiceOverEnabled
        let targets = windows.filter { frames[$0.info.id] != nil }
        let byPID = Dictionary(grouping: targets, by: \.pid)
        var errors: [WindowID: AXError] = [:]
        var restoreEnhancedUI: [AXUIElement] = []

        for (_, appWindows) in byPID {
            guard let app = appWindows.first?.appElement else { continue }
            // Chromium/Electron animate AX resizes while this is on; turn it off
            // until after the settle delay. Leave it alone for VoiceOver users.
            if !voiceOverOn, app.bool(AXAttr.enhancedUserInterface) == true {
                app.set(AXAttr.enhancedUserInterface, kCFBooleanFalse)
                restoreEnhancedUI.append(app)
            }

            for w in appWindows {
                guard let t = frames[w.info.id] else { continue }
                let size = CGSize(width: t.w, height: t.h)
                let resize = w.info.isResizable && !w.info.frame.size.isApproximately(t.size)
                if resize {
                    // size -> position -> size. The first resize is best effort:
                    // it lets the move land when the old position would overflow.
                    // Only the position and the final size decide the outcome.
                    w.element.set(size: size)
                }
                let movedErr = w.element.set(position: CGPoint(x: t.x, y: t.y))
                let sizedErr: AXError = resize ? w.element.set(size: size) : .success
                if movedErr != .success {
                    errors[w.info.id] = movedErr
                } else if sizedErr != .success {
                    errors[w.info.id] = sizedErr
                }
            }
        }

        try? await Task.sleep(for: settleDelay)

        let outcomes: [Outcome] = targets.compactMap { w in
            guard let t = frames[w.info.id] else { return nil }
            var actual: Rect?
            if let p = w.element.point(AXAttr.position), let s = w.element.size(AXAttr.size) {
                actual = Rect(x: p.x, y: p.y, w: s.width, h: s.height)
            }
            return Outcome(id: w.info.id, target: t, actual: actual, error: errors[w.info.id])
        }
        for app in restoreEnhancedUI { app.set(AXAttr.enhancedUserInterface, kCFBooleanTrue) }
        return outcomes
    }

    /// Restores previous frames (Undo).
    public func restore(_ snapshot: [WindowID: Rect], windows: [DiscoveredWindow]) async -> [Outcome] {
        await apply(snapshot, to: windows)
    }
}

extension Size {
    func isApproximately(_ other: Size, tolerance: Double = 1) -> Bool {
        abs(w - other.w) <= tolerance && abs(h - other.h) <= tolerance
    }
}
