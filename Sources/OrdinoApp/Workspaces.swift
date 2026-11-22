import AppKit
import Geometry
import KeyboardShortcuts
import LayoutEngine
import WindowKit

/// A saved arrangement: which apps go where, as fractions of a display's usable area, so it fits any display.
struct Workspace: Codable, Identifiable, Equatable {
    struct Slot: Codable, Equatable {
        var bundleID: String
        var appName: String
        /// Window frame as fractions (0...1) of the display's visible frame.
        var x: Double
        var y: Double
        var w: Double
        var h: Double
    }

    var id = UUID()
    var name: String
    var slots: [Slot]

    var shortcutName: KeyboardShortcuts.Name { .init("workspace-\(id.uuidString)") }
    var summary: String { slots.map(\.appName).joined(separator: ", ") }
}

/// Saves the windows of a display as a workspace, and brings a workspace back: missing apps are opened,
/// then each app's windows go to their slots on the display under the mouse.
@MainActor
final class WorkspaceController {
    enum ApplyResult {
        case placed(windows: Int, missing: [String])
        case nothingToPlace
    }

    private let settings: Settings
    private var registered: Set<UUID> = []
    private let mover = WindowMover()

    init(settings: Settings) {
        self.settings = settings
    }

    // MARK: Saving

    /// The windows on `display`, front to back, as a workspace named `name`.
    func capture(on display: DisplayInfo, name: String) -> Workspace? {
        let v = display.visibleFrame
        guard v.w > 0, v.h > 0 else { return nil }
        let windows = WindowDiscovery().windows(on: display, focusedID: nil).windows.sorted { $0.zIndex < $1.zIndex }
        let slots = windows.compactMap { w -> Workspace.Slot? in
            guard let bundleID = w.bundleID else { return nil }
            let f = w.info.frame
            return Workspace.Slot(
                bundleID: bundleID, appName: w.appName,
                x: (f.x - v.x) / v.w, y: (f.y - v.y) / v.h, w: f.w / v.w, h: f.h / v.h)
        }
        return slots.isEmpty ? nil : Workspace(name: name, slots: slots)
    }

    /// Asks for a name and saves the display under the mouse as a new workspace.
    func saveCurrent() -> Workspace? {
        guard let display = Displays.underMouse() else { return nil }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Save Workspace"
        alert.informativeText =
            "ordino remembers where each app's windows are on this display. Bring it back from the menu or with its own shortcut."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "Name, e.g. Coding"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let typed = field.stringValue.trimmingCharacters(in: .whitespaces)
        let name = typed.isEmpty ? "Workspace \(settings.workspaces.count + 1)" : typed
        guard let ws = capture(on: display, name: name) else { return nil }
        settings.workspaces.append(ws)
        return ws
    }

    // MARK: Applying

    func apply(_ ws: Workspace) async -> ApplyResult {
        guard let display = Displays.underMouse() ?? Displays.all().first else { return .nothingToPlace }
        let needed = Dictionary(grouping: ws.slots, by: \.bundleID)
        var missing: Set<String> = []

        // Open the apps that aren't running, in the background.
        for bundleID in needed.keys
        where NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                missing.insert(bundleID)
                continue
            }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: config)
        }

        // Wait (up to ~6 s) until every app shows as many windows as it has slots.
        var windows: [String: [DiscoveredWindow]] = [:]
        for attempt in 0..<24 {
            if attempt > 0 { try? await Task.sleep(for: .milliseconds(250)) }
            windows = Self.windowsByApp(Set(needed.keys))
            let ready = needed.allSatisfy { bundleID, slots in
                missing.contains(bundleID) || windows[bundleID, default: []].count >= slots.count
            }
            if ready { break }
        }

        // Slot i of an app gets its i-th window, front to back.
        let v = display.visibleFrame
        var frames: [WindowID: Rect] = [:]
        var targets: [DiscoveredWindow] = []
        for (bundleID, slots) in needed {
            for (slot, window) in zip(slots, windows[bundleID, default: []]) {
                frames[window.info.id] = Rect(
                    x: v.x + slot.x * v.w, y: v.y + slot.y * v.h, w: slot.w * v.w, h: slot.h * v.h)
                targets.append(window)
            }
        }
        let missingNames = missing.compactMap { needed[$0]?.first?.appName }.sorted()
        guard !frames.isEmpty else { return .nothingToPlace }
        _ = await mover.apply(frames, to: targets)
        return .placed(windows: frames.count, missing: missingNames)
    }

    /// Windows of the given apps on every display, front to back.
    private static func windowsByApp(_ bundleIDs: Set<String>) -> [String: [DiscoveredWindow]] {
        let all = Displays.all().flatMap { WindowDiscovery().windows(on: $0, focusedID: nil).windows }
        var result: [String: [DiscoveredWindow]] = [:]
        for w in all {
            guard let id = w.bundleID, bundleIDs.contains(id) else { continue }
            result[id, default: []].append(w)
        }
        return result.mapValues { $0.sorted { $0.zIndex < $1.zIndex } }
    }

    // MARK: Shortcuts

    /// Registers each workspace's shortcut handler once; a deleted workspace's handler finds nothing.
    func registerShortcuts(perform: @escaping @MainActor (UUID) -> Void) {
        for ws in settings.workspaces where !registered.contains(ws.id) {
            registered.insert(ws.id)
            let id = ws.id
            KeyboardShortcuts.onKeyDown(for: ws.shortcutName) { perform(id) }
        }
    }

    func delete(_ id: UUID) {
        if let ws = settings.workspaces.first(where: { $0.id == id }) { KeyboardShortcuts.reset(ws.shortcutName) }
        settings.workspaces.removeAll { $0.id == id }
    }
}
