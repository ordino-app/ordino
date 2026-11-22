import AppKit
import ArrangeCore
import Geometry
import KeyboardShortcuts
import LayoutEngine
import WindowKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = Settings()
    let backend = AXBackend()
    private(set) lazy var coordinator = ArrangeCoordinator(
        backend: backend, preferences: settings.preferences, preferredLayouts: settings.preferredLayouts)
    private(set) lazy var windowActions = WindowActionController(settings: settings)
    private(set) lazy var updater = Updater(settings: settings)
    private var menu: MenuController?
    private let hud = HUD()
    private var onboarding: OnboardingController?
    private lazy var settingsWindow = SettingsWindowController(app: self)

    /// A running window manager whose shortcuts collide with ours (shown in Settings).
    private(set) var conflictingWindowManager: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        FrontmostAppTracker.shared.start()
        NSApp.mainMenu = MainMenu.make(app: self)
        conflictingWindowManager = ShortcutPreset.runningWindowManager()
        syncSettings()
        settings.onLayoutChange = { [weak self] in self?.applyLayoutSettings() }
        applyLayoutSettings()
        setUpShortcutsIfNeeded()
        registerShortcutHandlers()
        menu = MenuController(app: self)
        updater.onChange = { [weak self] in self?.menu?.refresh() }
        observeSettings()
        observeDisplayChanges()
        #if DEBUG
            DebugSnapshots.runIfRequested(app: self)
            if UserDefaults.standard.string(forKey: "ordinoSnapshotDir") != nil { return }
        #endif
        if !AccessibilityPermission.isTrusted { showOnboarding() }
    }

    /// Launching ordino again (Finder, Spotlight) opens Settings, so it stays
    /// reachable when the menu bar icon is hidden or behind the notch.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if AccessibilityPermission.isTrusted { showSettings() } else { showOnboarding() }
        return false
    }

    // MARK: Commands

    func perform(_ command: Command) {
        switch command {
        case .arrange: run(.arrange, focusedID: WindowDiscovery.focusedWindowID())
        case .nextLayout: run(.nextLayout, focusedID: WindowDiscovery.focusedWindowID())
        case .previousLayout: run(.previousLayout, focusedID: WindowDiscovery.focusedWindowID())
        case .rotate: run(.rotate, focusedID: WindowDiscovery.focusedWindowID())
        case .undo: undo()
        case .window(let action): performWindowAction(action)
        }
    }

    /// - Parameters:
    ///   - focusedID: the window the user works in, captured before any ordino UI showed.
    ///   - primaryID: a window the user picked as primary in the menu.
    ///   - display: the display to arrange; `nil` = per the "Arrange" setting.
    func run(
        _ action: ArrangeCoordinator.Action, focusedID: WindowID?, primaryID: WindowID? = nil,
        display: DisplaySnapshot? = nil
    ) {
        guard AccessibilityPermission.isTrusted else {
            showOnboarding()
            return
        }
        let target = display ?? arrangeDisplay()
        Task {
            let outcome = await coordinator.perform(action, focusedID: focusedID, primaryID: primaryID, display: target)
            if case .arranged(let r) = outcome, let id = target?.id { lastLayouts[id] = r.layout }
            if let target { await applyAppRules(on: target) }
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
        }
    }

    private func performWindowAction(_ action: WindowAction) {
        guard AccessibilityPermission.isTrusted else {
            showOnboarding()
            return
        }
        Task {
            switch await windowActions.perform(action) {
            case .done(let action, let appName):
                if settings.showActionHUD { hud.show("\(action.title) · \(appName)") }
            case .noWindow: hud.show("No window to move")
            case .ignored(let appName): hud.show("ordino ignores \(appName) · change it in Settings › Apps")
            case .nothingToRestore: hud.show("Nothing to restore")
            case .singleDisplay: hud.show("Only one display is connected")
            case .notResizable(let appName): hud.show("\(appName) can't be resized")
            }
        }
    }

    // MARK: - Per-app rules

    /// Puts windows of apps with a rule (Settings › Apps › Rules) in their place on `display`.
    /// Those apps are excluded from layouts, so this runs after every arrange.
    func applyAppRules(on display: DisplaySnapshot) async {
        guard !settings.appRules.isEmpty, let info = Displays.all().first(where: { $0.uuid == display.id }) else {
            return
        }
        let engine = settings.windowActionEngine
        let windows = WindowDiscovery().windows(on: info, focusedID: nil).windows
        var frames: [WindowID: Rect] = [:]
        var ruled: [DiscoveredWindow] = []
        for w in windows {
            guard let id = w.bundleID, let raw = settings.appRules[id], let action = WindowAction(rawValue: raw),
                let frame = engine.frame(for: action, window: w.info.frame, area: info.visibleFrame)
            else { continue }
            frames[w.info.id] = frame
            ruled.append(w)
        }
        if !frames.isEmpty { _ = await WindowMover().apply(frames, to: ruled) }
    }

    func setRule(_ action: WindowAction?, bundleID: String) {
        settings.appRules[bundleID] = action?.rawValue
    }

    // MARK: - Displays connected or disconnected

    /// Last layout ordino applied on each display (by display UUID), for re-arranging after a display change.
    private var lastLayouts: [String: LayoutID] = [:]
    private var displayChangeTask: Task<Void, Never>?

    private func observeDisplayChanges() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.displaysChanged() }
        }
    }

    /// Waits for macOS to finish moving windows between displays, then puts each display that ordino
    /// arranged before back into its last layout. Displays ordino never arranged are left alone.
    private func displaysChanged() {
        displayChangeTask?.cancel()
        guard settings.rearrangeOnDisplayChange, AccessibilityPermission.isTrusted, !lastLayouts.isEmpty else { return }
        displayChangeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled else { return }
            var arranged = 0
            for info in Displays.all() {
                guard let layout = lastLayouts[info.uuid] else { continue }
                let display = DisplaySnapshot(id: info.uuid, name: info.name, visibleFrame: info.visibleFrame)
                if case .arranged = await coordinator.perform(.layout(layout), focusedID: nil, display: display) {
                    arranged += 1
                }
                await applyAppRules(on: display)
            }
            if arranged > 0, settings.showArrangeHUD {
                hud.show("Displays changed · re-arranged \(arranged) display\(arranged == 1 ? "" : "s")")
            }
            menu?.refresh()
        }
    }

    /// The display "Arrange" works on, per Settings › General.
    func arrangeDisplay() -> DisplaySnapshot? {
        let info: DisplayInfo? =
            switch settings.arrangeTarget {
            case .displayUnderMouse: Displays.underMouse()
            case .displayWithFocusedWindow:
                WindowDiscovery.focusedWindow().flatMap { Displays.containing($0.info.frame) } ?? Displays.underMouse()
            }
        return info.map { DisplaySnapshot(id: $0.uuid, name: $0.name, visibleFrame: $0.visibleFrame) }
    }

    func toggleIgnored(bundleID: String) {
        if settings.ignoredApps.contains(bundleID) {
            settings.ignoredApps.removeAll { $0 == bundleID }
        } else {
            settings.ignoredApps.append(bundleID)
        }
    }

    func forgetRememberedLayouts() {
        coordinator.forgetPreferredLayouts()
        settings.preferredLayouts = [:]
    }

    // MARK: Windows

    func showSettings(pane: SettingsPane = .general) {
        settingsWindow.show(pane: pane)
    }

    func showOnboarding() {
        if onboarding == nil {
            onboarding = OnboardingController { [weak self] in
                self?.onboarding = nil
                // Hand activation back to the app the user was in.
                NSApp.hide(nil)
                self?.menu?.refresh()
            }
        }
        onboarding?.show()
    }

    // MARK: Settings plumbing

    private func applyLayoutSettings() {
        coordinator.preferences = settings.preferences
        coordinator.cycleInterval = settings.cycleOnRepeat ? .seconds(2) : .zero
    }

    private func syncSettings() {
        backend.excludedBundleIDs = Set(settings.ignoredApps).union(settings.appRules.keys)
        coordinator.preferredPrimaryApps = settings.primaryApps
        menu?.setVisible(settings.showMenuBarIcon)
    }

    /// Re-syncs whenever an app-level setting changes.
    private func observeSettings() {
        withObservationTracking {
            _ = settings.ignoredApps
            _ = settings.appRules
            _ = settings.primaryApps
            _ = settings.showMenuBarIcon
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.syncSettings()
                self?.observeSettings()
            }
        }
    }

    // MARK: Shortcuts

    /// First launch of this version: ordino's own shortcuts, plus window-action
    /// shortcuts only for new users with no other window manager running.
    /// Upgraders keep what they had (no new global shortcuts taken without asking,
    /// and next/previous layout stay on ⌃⌥⌘←/→); they can pick a preset in Settings.
    private func setUpShortcutsIfNeeded() {
        guard settings.needsShortcutSetup else { return }
        ShortcutPreset.applyArrangeDefaults()
        if settings.isUpgradeFromEarlierVersion {
            for (command, shortcut) in ShortcutPreset.legacyLayoutCycling {
                KeyboardShortcuts.setShortcut(shortcut, for: command.shortcutName)
            }
            settings.shortcutPreset = .none
        } else if conflictingWindowManager != nil {
            settings.shortcutPreset = .none
        }
        settings.shortcutPreset.apply()
        settings.needsShortcutSetup = false
    }

    private func registerShortcutHandlers() {
        for command in Command.all {
            KeyboardShortcuts.onKeyDown(for: command.shortcutName) { [weak self] in
                self?.perform(command)
            }
        }
    }

    // MARK: Messages

    func message(for outcome: ArrangeCoordinator.Outcome) -> String? {
        switch outcome {
        case .arranged(let r):
            guard settings.showArrangeHUD || !r.mismatchedIDs.isEmpty else { return nil }
            var parts = ["Arranged \(r.windowCount) window\(r.windowCount == 1 ? "" : "s")", r.layout.description]
            if !r.mismatchedIDs.isEmpty { parts.append("\(r.mismatchedIDs.count) didn't fit exactly") }
            if r.unplacedCount > 0 { parts.append("\(r.unplacedCount) left as is") }
            if let undo = KeyboardShortcuts.getShortcut(for: Command.undo.shortcutName) {
                parts.append("\(undo) to undo")
            }
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
