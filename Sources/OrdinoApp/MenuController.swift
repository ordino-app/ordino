import AppKit
import ArrangeCore
import LayoutEngine
import SwiftUI
import WindowKit

/// State shown in the menu panel.
@MainActor
@Observable
final class MenuModel {
    var trusted = AccessibilityPermission.isTrusted
    var preview: ArrangeCoordinator.Preview?
    /// Layout picked in the alternatives row by hover, arrow keys or 1-9.
    var selectedLayout: LayoutID?
    /// Selection that survives the mouse leaving the alternatives row
    /// (set by arrow keys or by picking a primary window).
    var stickyLayout: LayoutID?
    var selectedPreview: ArrangeCoordinator.Preview?
    var gap: Double = 8
    var launchAtLogin = false
    var canUndo = false
    var arrangeHint: String? = "⌃⌥⌘A"
    /// Window the user picked as primary in this menu session (`nil` = automatic).
    var primaryOverride: WindowID?
    var alwaysPrimaryApps: [String] = []
    var updatesAvailable = false
    var updateAvailable = false
    var canCheckForUpdates = false
    var betaUpdates = false
    var version = ""

    var shortcutWarning: String?

    var shownPreview: ArrangeCoordinator.Preview? { selectedPreview ?? preview }
    /// The layout Arrange will apply: exactly what the thumbnail shows.
    var layoutToApply: LayoutID? { shownPreview?.plan.layout }
}

/// A panel that takes clicks and keys without activating ordino, so the user's
/// app stays frontmost and its focused window stays the master candidate.
final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class MenuController: NSObject {
    private unowned let app: AppDelegate
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let model = MenuModel()
    private var panel: NonActivatingPanel?
    private var monitors: [Any] = []
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    /// Captured when the menu opens, so preview and arrange agree.
    private var focusedID: WindowID?
    private var display: DisplaySnapshot?

    init(app: AppDelegate) {
        self.app = app
        super.init()
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "rectangle.split.2x2", accessibilityDescription: "ordino")
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(toggle)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("ordino")
        }
    }

    var isOpen: Bool { panel?.isVisible == true }

    /// A small dot on the menu bar icon when an update is waiting.
    private func updateStatusIcon() {
        let name = app.updater.updateAvailable ? "rectangle.split.2x2.fill" : "rectangle.split.2x2"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "ordino")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.setAccessibilityLabel(app.updater.updateAvailable ? "ordino, update available" : "ordino")
    }

    @objc private func toggle() {
        if isOpen { close() } else { show() }
    }

    func show() {
        focusedID = WindowDiscovery.focusedWindowID()
        display = app.backend.targetDisplay()
        model.selectedLayout = nil
        model.selectedPreview = nil
        model.primaryOverride = nil
        model.stickyLayout = nil
        let panel = self.panel ?? makePanel()
        self.panel = panel
        refresh(force: true)
        position(panel)
        panel.orderFrontRegardless()
        panel.makeKey()
        installMonitors()
    }

    func close() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        removeMonitors()
        model.selectedLayout = nil
        model.selectedPreview = nil
    }

    /// Updates the menu. The (comparatively expensive) preview is only computed
    /// while the panel is visible.
    func refresh(force: Bool = false) {
        model.trusted = AccessibilityPermission.isTrusted
        model.gap = app.settings.gap
        model.launchAtLogin = app.settings.launchAtLogin
        model.canUndo = app.coordinator.canUndo
        model.alwaysPrimaryApps = app.settings.primaryApps
        model.updatesAvailable = app.updater.isAvailable
        model.updateAvailable = app.updater.updateAvailable
        model.canCheckForUpdates = app.updater.canCheck
        model.betaUpdates = app.settings.betaUpdates
        let info = Bundle.main.infoDictionary
        model.version = (info?["CFBundleShortVersionString"] as? String).map { "Version \($0)" } ?? "Development build"
        updateStatusIcon()
        model.arrangeHint = app.arrangeShortcutAvailable ? "⌃⌥⌘A" : nil
        model.shortcutWarning =
            app.unavailableShortcuts.isEmpty
            ? nil
            : "\(app.unavailableShortcuts.joined(separator: ", ")) already used by another app"
        guard force || isOpen else { return }
        model.preview =
            model.trusted
            ? app.coordinator.preview(focusedID: focusedID, primaryID: model.primaryOverride, display: display) : nil
        // Forget a picked window that has since closed or left the display.
        if let id = model.primaryOverride, model.preview?.windowIDs.contains(id) != true {
            model.primaryOverride = nil
        }
        if let selected = model.selectedLayout { select(selected) }
        resizePanel()
    }

    // MARK: Actions

    private func arrange(_ layout: LayoutID?) {
        guard let layout = layout ?? model.layoutToApply else { return }
        let focused = focusedID
        let target = display
        let primary = model.primaryOverride
        close()
        app.run(.layout(layout), focusedID: focused, primaryID: primary, display: target)
    }

    private func select(_ layout: LayoutID?) {
        model.selectedLayout = layout
        model.selectedPreview = layout.flatMap {
            app.coordinator.preview(
                focusedID: focusedID, primaryID: model.primaryOverride, display: display, action: .layout($0))
        }
    }

    /// Picks the primary window for this arrange (`nil` = automatic). A primary
    /// window only matters for Master + Stack, so picking one switches to it.
    private func setPrimary(_ id: WindowID?) {
        model.primaryOverride = id
        if id != nil {
            model.stickyLayout = .masterStack
            model.selectedLayout = .masterStack
        }
        refresh()
    }

    /// Hover enters (`layout`) or leaves (`nil`) an alternative.
    private func hover(_ layout: LayoutID?) {
        select(layout ?? model.stickyLayout)
    }

    private func setAlwaysPrimary(_ bundleID: String, _ on: Bool) {
        app.setAlwaysPrimary(bundleID, on)
        refresh()
    }

    private func moveSelection(by offset: Int) {
        guard let candidates = model.preview?.plan.candidates, !candidates.isEmpty else { return }
        let current = model.selectedLayout ?? model.preview?.plan.layout
        let i = current.flatMap { candidates.firstIndex(of: $0) } ?? 0
        let n = candidates.count
        let next = candidates[((i + offset) % n + n) % n]
        model.stickyLayout = next
        select(next)
    }

    // MARK: Panel

    private func makePanel() -> NonActivatingPanel {
        let panel = NonActivatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 300),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        let view = MenuView(
            model: model,
            onArrange: { [weak self] in self?.arrange($0) },
            onSelect: { [weak self] in self?.hover($0) },
            onPrimary: { [weak self] in self?.setPrimary($0) },
            onAlwaysPrimary: { [weak self] in self?.setAlwaysPrimary($0, $1) },
            onUndo: { [weak self] in
                self?.close()
                self?.app.undo()
            },
            onGap: { [weak self] in
                self?.app.setGap($0)
                self?.refresh()
            },
            onLaunchAtLogin: { [weak self] in
                self?.app.settings.launchAtLogin = $0
                self?.refresh()
            },
            onGrantAccess: { [weak self] in self?.app.showOnboarding() },
            onCheckForUpdates: { [weak self] in
                self?.close()
                self?.app.updater.checkForUpdates()
            },
            onBetaUpdates: { [weak self] in
                self?.app.settings.betaUpdates = $0
                self?.refresh()
            },
            onQuit: { NSApp.terminate(nil) })
        panel.contentView = NSHostingView(rootView: view)
        return panel
    }

    private func resizePanel() {
        guard let panel, let hosting = panel.contentView else { return }
        let size = hosting.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        var frame = panel.frame
        frame.origin.y += frame.height - size.height  // grow downwards from the menu bar
        frame.size = size
        panel.setFrame(frame, display: true)
    }

    private func position(_ panel: NSPanel) {
        guard let button = statusItem.button, let window = button.window else { return }
        if let hosting = panel.contentView { panel.setContentSize(hosting.fittingSize) }
        let buttonFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
        let size = panel.frame.size
        var origin = NSPoint(x: buttonFrame.midX - size.width / 2, y: buttonFrame.minY - size.height - 6)
        if let screen = window.screen {
            let v = screen.visibleFrame
            origin.x = min(max(origin.x, v.minX + 8), v.maxX - size.width - 8)
        }
        panel.setFrameOrigin(origin)
    }

    // MARK: Closing and keyboard

    private func installMonitors() {
        removeMonitors()
        if let m = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown],
            handler: {
                [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            })
        {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown,
            handler: { [weak self] event in
                let consumed = MainActor.assumeIsolated { self?.handleKey(event) ?? false }
                return consumed ? nil : event
            })
        {
            monitors.append(m)
        }

        // Close when focus moves elsewhere without a click: Cmd-Tab, Space switch, hotkeys.
        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        let closeHandler: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        if let panel {
            observers.append(
                (
                    center,
                    center.addObserver(
                        forName: NSWindow.didResignKeyNotification, object: panel, queue: .main, using: closeHandler)
                ))
        }
        observers.append(
            (
                workspace,
                workspace.addObserver(
                    forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main,
                    using: closeHandler)
            ))
        observers.append(
            (
                workspace,
                workspace.addObserver(
                    forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main,
                    using: closeHandler)
            ))
    }

    private func removeMonitors() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors.removeAll()
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
    }

    /// Esc closes, ←/→ pick a layout, 1-9 apply one directly, Return applies the
    /// shown layout, ⌘Z undoes.
    /// Returns true when the key was handled.
    private func handleKey(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 53:  // Esc
            close()
            return true
        case 36, 76:  // Return, Enter
            arrange(nil)
            return true
        case 123:  // ←
            moveSelection(by: -1)
            return true
        case 124:  // →
            moveSelection(by: 1)
            return true
        default:
            break
        }
        if mods == .command, event.charactersIgnoringModifiers == "z" {
            close()
            app.undo()
            return true
        }
        if mods.isEmpty, let chars = event.charactersIgnoringModifiers, let digit = Int(chars), (1...9).contains(digit),
            let candidates = model.preview?.plan.candidates, digit <= candidates.count
        {
            arrange(candidates[digit - 1])
            return true
        }
        return false
    }
}
