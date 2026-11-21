import AppKit
import ArrangeCore
import Carbon.HIToolbox
import LayoutEngine
import WindowKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = Settings()
    let backend = AXBackend()
    private(set) lazy var coordinator = ArrangeCoordinator(
        backend: backend, preferences: settings.preferences, preferredLayouts: settings.preferredLayouts)
    private var menu: MenuController?
    private let hud = HUD()
    private var onboarding: OnboardingController?
    private(set) lazy var updater = Updater(settings: settings)

    /// Shortcuts that another app already owns. Shown in the menu; never advertised in hints.
    private(set) var unavailableShortcuts: [String] = []
    var undoShortcutAvailable: Bool { !unavailableShortcuts.contains("⌃⌥⌘Z") }
    var arrangeShortcutAvailable: Bool { !unavailableShortcuts.contains("⌃⌥⌘A") }

    func applicationDidFinishLaunching(_ notification: Notification) {
        FrontmostAppTracker.shared.start()
        backend.excludedBundleIDs = settings.excludedBundleIDs
        coordinator.preferredPrimaryApps = settings.primaryApps
        menu = MenuController(app: self)
        updater.onChange = { [weak self] in self?.menu?.refresh() }
        registerHotKeys()
        if !AccessibilityPermission.isTrusted { showOnboarding() }
    }

    /// Launching the app again (Finder, Spotlight) opens the menu, so ordino is
    /// reachable even when the menu bar icon is hidden behind the notch.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if AccessibilityPermission.isTrusted { menu?.show() } else { showOnboarding() }
        return false
    }

    // MARK: Actions

    /// - Parameters:
    ///   - focusedID: the window that becomes master, captured before any ordino UI showed.
    ///   - primaryID: a window the user picked as primary in the menu.
    ///   - display: the display to arrange; `nil` = the one under the mouse.
    func run(
        _ action: ArrangeCoordinator.Action, focusedID: WindowID?, primaryID: WindowID? = nil,
        display: DisplaySnapshot? = nil
    ) {
        guard AccessibilityPermission.isTrusted else {
            showOnboarding()
            return
        }
        Task {
            let outcome = await coordinator.perform(
                action, focusedID: focusedID, primaryID: primaryID, display: display)
            settings.preferredLayouts = coordinator.preferredLayouts
            if let text = message(for: outcome) { hud.show(text) }
            menu?.refresh()
        }
    }

    func undo() {
        Task {
            switch await coordinator.undo() {
            case .restored(let n): hud.show("Restored \(n) window\(n == 1 ? "" : "s")")
            case .nothingToUndo: hud.show("Nothing to undo")
            case .busy: break
            }
            settings.preferredLayouts = coordinator.preferredLayouts
            menu?.refresh()
        }
    }

    /// Adds or removes an app from the "always primary" list (added apps go first).
    func setAlwaysPrimary(_ bundleID: String, _ on: Bool) {
        var apps = settings.primaryApps.filter { $0 != bundleID }
        if on { apps.insert(bundleID, at: 0) }
        settings.primaryApps = apps
        coordinator.preferredPrimaryApps = apps
    }

    func setGap(_ gap: Double) {
        settings.gap = gap
        coordinator.preferences = settings.preferences
    }

    func showOnboarding() {
        menu?.close()
        if onboarding == nil {
            onboarding = OnboardingController { [weak self] in
                self?.onboarding = nil
                // Hand activation back to the app the user was in, so its window
                // is the master for the first arrange.
                NSApp.hide(nil)
                self?.menu?.refresh()
            }
        }
        onboarding?.show()
    }

    // MARK: Hotkeys

    private func registerHotKeys() {
        let keys = HotKeys.shared
        let actions: [(HotKeys.Combo, String, ArrangeCoordinator.Action)] = [
            (.hyper(kVK_ANSI_A), "⌃⌥⌘A", .arrange),
            (.hyper(kVK_RightArrow), "⌃⌥⌘→", .nextLayout),
            (.hyper(kVK_LeftArrow), "⌃⌥⌘←", .previousLayout),
            (.hyper(kVK_ANSI_R), "⌃⌥⌘R", .rotate),
        ]
        for (combo, label, action) in actions {
            let ok = keys.register(combo) { [weak self] in
                self?.menu?.close()
                self?.run(action, focusedID: WindowDiscovery.focusedWindowID())
            }
            if !ok { unavailableShortcuts.append(label) }
        }
        let undoOK = keys.register(.hyper(kVK_ANSI_Z)) { [weak self] in
            self?.menu?.close()
            self?.undo()
        }
        if !undoOK { unavailableShortcuts.append("⌃⌥⌘Z") }
        if !unavailableShortcuts.isEmpty {
            NSLog("ordino: shortcuts already in use by another app: \(unavailableShortcuts.joined(separator: ", "))")
        }
    }

    // MARK: Messages

    func message(for outcome: ArrangeCoordinator.Outcome) -> String? {
        switch outcome {
        case .arranged(let r):
            var parts = ["Arranged \(r.windowCount) window\(r.windowCount == 1 ? "" : "s")", r.layout.description]
            if !r.mismatchedIDs.isEmpty { parts.append("\(r.mismatchedIDs.count) didn't fit exactly") }
            if r.unplacedCount > 0 { parts.append("\(r.unplacedCount) left as is") }
            parts.append(undoShortcutAvailable ? "⌃⌥⌘Z to undo" : "Undo in the menu")
            return parts.joined(separator: " · ")
        case .nothingToArrange(let name):
            return "No windows to arrange on \(name). Full-screen windows and other Spaces aren't included."
        case .noDisplay:
            return "No display found"
        case .busy:
            return nil
        }
    }
}
