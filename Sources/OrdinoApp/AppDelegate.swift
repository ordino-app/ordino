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
    private(set) lazy var workspaces = WorkspaceController(settings: settings)
    private(set) lazy var customLayouts = CustomLayoutController(settings: settings)
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
        observeRuledApps()
        workspaces.registerShortcuts { [weak self] in self?.applyWorkspace($0) }
        registerCustomLayoutShortcuts()
        dragSnap = DragSnapController(settings: settings, windowActions: windowActions) { [weak self] outcome in
            if case .done(let action, let appName) = outcome, self?.settings.showActionHUD == true {
                self?.hud.show("\(action.title) · \(appName)")
            }
        }
        syncDragSnap()
        #if DEBUG
            DebugSnapshots.runIfRequested(app: self)
            if UserDefaults.standard.string(forKey: "ordinoSnapshotDir") != nil { return }
        #endif
        if !AccessibilityPermission.isTrusted { showOnboarding() }
    }

    /// `ordino://` links from Shortcuts.app, Raycast or scripts (see `AutomationURL`).
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let request = AutomationURL(url) else {
                hud.show("Unknown ordino link: \(url.absoluteString)")
                continue
            }
            handle(request)
        }
    }

    private func handle(_ request: AutomationURL) {
        let focused = WindowDiscovery.focusedWindowID()
        switch request {
        case .arrange(let recent): run(.arrange, focusedID: focused, limit: recent)
        case .layout(let layout): run(.layout(layout), focusedID: focused)
        case .nextLayout: run(.nextLayout, focusedID: focused)
        case .previousLayout: run(.previousLayout, focusedID: focused)
        case .rotate: run(.rotate, focusedID: focused)
        case .undo: undo()
        case .window(let action): performWindowAction(action)
        case .workspace(let name):
            if let ws = settings.workspaces.first(where: { $0.name.lowercased() == name.lowercased() }) {
                applyWorkspace(ws.id)
            } else {
                hud.show("No workspace named \(name)")
            }
        case .custom(let name):
            if let l = settings.customLayouts.first(where: { $0.name.lowercased() == name.lowercased() }) {
                applyCustomLayout(l.id)
            } else {
                hud.show("No custom layout named \(name)")
            }
        }
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
        case .arrangeRecent(let n): run(.arrange, focusedID: WindowDiscovery.focusedWindowID(), limit: n)
        case .window(let action): performWindowAction(action)
        }
    }

    /// - Parameters:
    ///   - focusedID: the window the user works in, captured before any ordino UI showed.
    ///   - primaryID: a window the user picked as primary in the menu.
    ///   - display: the display to arrange; `nil` = per the "Arrange" setting.
    func run(
        _ action: ArrangeCoordinator.Action, focusedID: WindowID?, primaryID: WindowID? = nil,
        display: DisplaySnapshot? = nil, limit: Int? = nil
    ) {
        guard AccessibilityPermission.isTrusted else {
            showOnboarding()
            return
        }
        let target = display ?? arrangeDisplay()
        Task {
            let area = target.map(layoutArea(for:))
            backend.windowLimit = limit
            coordinator.spaceID = Spaces.activeSpaceID()
            let outcome = await coordinator.perform(action, focusedID: focusedID, primaryID: primaryID, display: area)
            backend.windowLimit = nil
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

    private var dragSnap: DragSnapController?

    /// Drag-to-snap runs only when enabled and no other window manager (Rectangle & co.) is running,
    /// so two apps never fight over the same drag.
    private func syncDragSnap() {
        if settings.snapOnDrag && conflictingWindowManager == nil { dragSnap?.start() } else { dragSnap?.stop() }
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
        guard let info = Displays.all().first(where: { $0.uuid == display.id }) else { return }
        let placed = ruledPlacements(on: info)
        guard !placed.isEmpty else { return }
        _ = await WindowMover().apply(
            Dictionary(placed.map { ($0.window.info.id, $0.frame) }, uniquingKeysWith: { a, _ in a }),
            to: placed.map(\.window))
        placedByRule.formUnion(placed.map(\.window.info.id))
    }

    /// Windows on `info` whose app has a rule, with the frame the rule gives them.
    private func ruledPlacements(on info: DisplayInfo, only bundleID: String? = nil)
        -> [(window: DiscoveredWindow, frame: Rect)]
    {
        guard !settings.appRules.isEmpty else { return [] }
        let engine = settings.windowActionEngine
        return WindowDiscovery().windows(on: info, focusedID: nil).windows.compactMap { w in
            guard let id = w.bundleID, bundleID == nil || id == bundleID,
                let raw = settings.appRules[id], let action = WindowAction(rawValue: raw),
                let frame = engine.frame(for: action, window: w.info.frame, area: info.visibleFrame)
            else { return nil }
            return (w, frame)
        }
    }

    /// The display to arrange, shrunk to the free part next to windows placed by rules, so the layout
    /// doesn't cover them. Falls back to the whole display when too little would be left.
    private func layoutArea(for display: DisplaySnapshot) -> DisplaySnapshot {
        guard let info = Displays.all().first(where: { $0.uuid == display.id }) else { return display }
        let obstacles = ruledPlacements(on: info).map(\.frame)
        guard !obstacles.isEmpty else { return display }
        let free = FreeArea.largest(in: display.visibleFrame, avoiding: obstacles)
        guard free.w >= 400, free.h >= 300 else { return display }
        return DisplaySnapshot(id: display.id, name: display.name, visibleFrame: free)
    }

    // MARK: - Workspaces

    func applyWorkspace(_ id: UUID) {
        guard let ws = settings.workspaces.first(where: { $0.id == id }) else { return }
        guard AccessibilityPermission.isTrusted else { return showOnboarding() }
        Task {
            switch await workspaces.apply(ws) {
            case .placed(let n, let missing):
                var text = "\(ws.name) · \(n) window\(n == 1 ? "" : "s")"
                if !missing.isEmpty { text += " · not installed: \(missing.joined(separator: ", "))" }
                hud.show(text)
            case .nothingToPlace:
                hud.show("\(ws.name) · no windows to place")
            }
        }
    }

    func applyCustomLayout(_ id: UUID) {
        guard let layout = settings.customLayouts.first(where: { $0.id == id }) else { return }
        guard AccessibilityPermission.isTrusted else { return showOnboarding() }
        guard let target = arrangeDisplay(), let info = Displays.all().first(where: { $0.uuid == target.id }) else {
            return
        }
        Task {
            let n = await customLayouts.apply(layout, on: info)
            hud.show(n == 0 ? "No windows to arrange" : "\(layout.name) · \(n) window\(n == 1 ? "" : "s")")
        }
    }

    func registerCustomLayoutShortcuts() {
        customLayouts.registerShortcuts { [weak self] in self?.applyCustomLayout($0) }
    }

    func saveWorkspace() {
        guard AccessibilityPermission.isTrusted else { return showOnboarding() }
        if let ws = workspaces.saveCurrent() {
            workspaces.registerShortcuts { [weak self] in self?.applyWorkspace($0) }
            hud.show("Saved \(ws.name) · \(ws.slots.count) window\(ws.slots.count == 1 ? "" : "s")")
            menu?.refresh()
        }
    }

    // MARK: - Rules for windows that appear later

    /// Windows already put in place by a rule; new windows of a ruled app are placed once, then left to the user.
    private var placedByRule: Set<WindowID> = []

    private func observeRuledApps() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didActivateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let bundleID = app?.bundleIdentifier
                MainActor.assumeIsolated { self?.placeNewWindows(of: bundleID) }
            }
        }
    }

    /// Puts windows of a ruled app that ordino hasn't placed yet in their place. Runs when the app launches or
    /// comes to the front (a new window brings its app forward), retrying briefly while a launch opens its window.
    private func placeNewWindows(of bundleID: String?) {
        guard let bundleID, settings.appRules[bundleID] != nil, AccessibilityPermission.isTrusted else { return }
        Task {
            for attempt in 0..<8 {
                if attempt > 0 { try? await Task.sleep(for: .milliseconds(500)) }
                var fresh: [(window: DiscoveredWindow, frame: Rect)] = []
                for info in Displays.all() {
                    fresh += ruledPlacements(on: info, only: bundleID).filter {
                        !placedByRule.contains($0.window.info.id)
                    }
                }
                guard !fresh.isEmpty else { continue }
                _ = await WindowMover().apply(
                    Dictionary(fresh.map { ($0.window.info.id, $0.frame) }, uniquingKeysWith: { a, _ in a }),
                    to: fresh.map(\.window))
                placedByRule.formUnion(fresh.map(\.window.info.id))
                return
            }
        }
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
                if case .arranged = await coordinator.perform(
                    .layout(layout), focusedID: nil, display: layoutArea(for: display))
                {
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
        menu?.refresh()
        syncDragSnap()
    }

    /// Re-syncs whenever an app-level setting changes.
    private func observeSettings() {
        withObservationTracking {
            _ = settings.ignoredApps
            _ = settings.appRules
            _ = settings.snapOnDrag
            _ = settings.primaryApps
            _ = settings.showMenuBarIcon
            _ = settings.menuBarIconStyle
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
        guard settings.needsShortcutSetup else { return ShortcutPreset.migrateMainShortcuts() }
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
        UserDefaults.standard.set(true, forKey: "mainShortcutsMigrated")
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
