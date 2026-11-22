import AppKit
import ArrangeCore
import KeyboardShortcuts
import LayoutEngine
import SwiftUI
import WindowKit

/// The status item and its native menu: an arrange card on top, then window
/// actions with their live shortcuts (like Rectangle), then app commands.
///
/// Opening an NSMenu doesn't activate ordino, so the user's app stays
/// frontmost and its focused window is the one actions apply to.
@MainActor
final class MenuController: NSObject, NSMenuDelegate {
    private unowned let app: AppDelegate
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private let card = MenuCardModel()
    private var cardHost: NSHostingView<MenuCard>?
    /// Captured when the menu opens, so preview and arrange agree.
    private var focusedID: WindowID?
    private var display: DisplaySnapshot?
    private var primaryOverride: WindowID?

    init(app: AppDelegate) {
        self.app = app
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        setVisible(app.settings.showMenuBarIcon)
    }

    func setVisible(_ visible: Bool) {
        if visible, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.menu = menu
            item.button?.setAccessibilityLabel("ordino")
            statusItem = item
            refreshIcon()
        } else if !visible, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    /// Opens the menu programmatically (relaunching ordino from Finder).
    func show() {
        statusItem?.button?.performClick(nil)
    }

    func refresh() { refreshIcon() }

    private func refreshIcon() {
        guard let button = statusItem?.button else { return }
        let updateWaiting = app.updater.updateAvailable
        var image = Bundle.main.image(forResource: "MenuBarIcon")
        if image == nil || updateWaiting {
            image = NSImage(
                systemSymbolName: updateWaiting ? "rectangle.split.2x2.fill" : "rectangle.split.2x2",
                accessibilityDescription: "ordino")
        }
        image?.isTemplate = true
        button.image = image
        button.setAccessibilityLabel(updateWaiting ? "ordino, update available" : "ordino")
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        focusedID = WindowDiscovery.focusedWindowID()
        display = app.arrangeDisplay()
        primaryOverride = nil
        card.hoveredLayout = nil
        card.hoverPreview = nil
        rebuild()
    }

    func menuDidClose(_ menu: NSMenu) {
        card.hoverPreview = nil
        card.hoveredLayout = nil
    }

    // MARK: Building the menu

    private func rebuild() {
        menu.removeAllItems()
        let trusted = AccessibilityPermission.isTrusted

        if trusted {
            card.preview = app.coordinator.preview(focusedID: focusedID, display: display)
            menu.addItem(cardItem())
            menu.addItem(.separator())
            addArrangeItems()
        } else {
            let grant = item("Grant Accessibility Access…", symbol: "exclamationmark.triangle") { [weak self] in
                self?.app.showOnboarding()
            }
            menu.addItem(grant)
            let note = NSMenuItem(title: "ordino needs it to move windows.", action: nil, keyEquivalent: "")
            note.isEnabled = false
            menu.addItem(note)
        }

        menu.addItem(.separator())
        addWindowActions(enabled: trusted)
        menu.addItem(.separator())

        if let frontmost = frontmostApp() {
            let ignored = app.settings.ignoredApps.contains(frontmost.bundleID)
            let ignore = item("Ignore \(frontmost.name)") { [weak self] in
                self?.app.toggleIgnored(bundleID: frontmost.bundleID)
            }
            ignore.state = ignored ? .on : .off
            menu.addItem(ignore)
            menu.addItem(ruleMenu(for: frontmost.bundleID, name: frontmost.name))
            menu.addItem(.separator())
        }

        let settings = item("Settings…") { [weak self] in self?.app.showSettings() }
        settings.keyEquivalent = ","
        settings.keyEquivalentModifierMask = .command
        menu.addItem(settings)
        menu.addItem(item("About ordino") { [weak self] in self?.app.showSettings(pane: .about) })
        if app.updater.isAvailable {
            let title = app.updater.updateAvailable ? "Update Available…" : "Check for Updates…"
            let update = item(title) { [weak self] in self?.app.updater.checkForUpdates() }
            update.isEnabled = app.updater.canCheck || app.updater.updateAvailable
            if app.updater.updateAvailable {
                update.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)
            }
            menu.addItem(update)
        }
        menu.addItem(.separator())
        let quit = item("Quit ordino") { NSApp.terminate(nil) }
        quit.keyEquivalent = "q"
        quit.keyEquivalentModifierMask = .command
        menu.addItem(quit)
    }

    private func cardItem() -> NSMenuItem {
        let view = MenuCard(
            model: card,
            arrangeShortcut: KeyboardShortcuts.getShortcut(for: Command.arrange.shortcutName)?.description,
            onArrange: { [weak self] layout in self?.arrange(layout) },
            onHover: { [weak self] layout in self?.hover(layout) },
            onPickPrimary: { [weak self] id in self?.pickPrimary(id) })
        let host = cardHost ?? NSHostingView(rootView: view)
        host.rootView = view
        host.frame.size = host.fittingSize
        cardHost = host
        let item = NSMenuItem()
        item.view = host
        return item
    }

    private func addArrangeItems() {
        let preview = card.preview
        let arrange = commandItem(.arrange) { [weak self] in self?.arrange(preview?.plan.layout) }
        arrange.isEnabled = preview != nil
        menu.addItem(arrange)

        if let preview {
            // Layout submenu: every alternative for this window count.
            let layouts = NSMenu()
            for layout in preview.plan.candidates {
                let entry = item(layout.description) { [weak self] in self?.arrange(layout) }
                entry.image = ActionIcons.image(for: layout, windowCount: preview.windowIDs.count)
                entry.state = layout == preview.plan.layout ? .on : .off
                layouts.addItem(entry)
            }
            menu.addItem(submenu("Layout", layouts))

            // Primary window: only meaningful for Master + Stack.
            if preview.plan.candidates.contains(.masterStack), preview.windowIDs.count > 1 {
                let primary = NSMenu()
                let automatic = item("Automatic (\(autoPrimaryName(preview)))") { [weak self] in
                    self?.primaryOverride = nil
                    self?.arrange(.masterStack)
                }
                automatic.state = primaryOverride == nil ? .on : .off
                primary.addItem(automatic)
                primary.addItem(.separator())
                for id in preview.windowIDs {
                    let entry = item(windowLabel(id, preview)) { [weak self] in
                        self?.pickPrimary(id, arrangeNow: true)
                    }
                    entry.state = primaryOverride == id ? .on : .off
                    if let bundleID = preview.bundleIDs[id],
                        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map({
                            NSWorkspace.shared.icon(forFile: $0.path)
                        })
                    {
                        icon.size = NSSize(width: 16, height: 16)
                        entry.image = icon
                    }
                    primary.addItem(entry)
                }
                menu.addItem(submenu("Primary Window", primary))
            }
        }

        menu.addItem(commandItem(.rotate) { [weak self] in self?.run(.rotate) })
        let undo = commandItem(.undo) { [weak self] in self?.app.undo() }
        undo.isEnabled = app.coordinator.canUndo
        menu.addItem(undo)
    }

    private func addWindowActions(enabled: Bool) {
        let sections: [[WindowAction]] = [
            [.leftHalf, .rightHalf, .centerHalf, .topHalf, .bottomHalf],
            [.topLeft, .topRight, .bottomLeft, .bottomRight],
            [.firstThird, .centerThird, .lastThird, .firstTwoThirds, .centerTwoThirds, .lastTwoThirds],
            [.maximize, .almostMaximize, .maximizeHeight, .larger, .smaller, .center, .restore],
            [.nextDisplay, .previousDisplay],
        ]
        let multipleDisplays = Displays.all().count > 1
        for (index, section) in sections.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            for action in section {
                let entry = actionItem(action)
                let needsDisplays = action == .nextDisplay || action == .previousDisplay
                entry.isEnabled = enabled && (!needsDisplays || multipleDisplays)
                menu.addItem(entry)
            }
        }
        menu.addItem(.separator())
        let groups: [(String, [WindowAction])] = [
            ("Move to Edge", [.moveLeft, .moveRight, .moveUp, .moveDown]),
            (
                "Fourths",
                [.firstFourth, .secondFourth, .thirdFourth, .lastFourth, .firstThreeFourths, .lastThreeFourths]
            ),
            (
                "Sixths",
                [
                    .topLeftSixth, .topCenterSixth, .topRightSixth, .bottomLeftSixth, .bottomCenterSixth,
                    .bottomRightSixth,
                ]
            ),
        ]
        for (title, actions) in groups {
            let sub = NSMenu()
            sub.autoenablesItems = false
            for action in actions {
                let entry = actionItem(action)
                entry.isEnabled = enabled
                sub.addItem(entry)
            }
            let parent = submenu(title, sub)
            parent.isEnabled = enabled
            menu.addItem(parent)
        }
    }

    // MARK: Actions

    private func run(_ action: ArrangeCoordinator.Action) {
        app.run(action, focusedID: focusedID, primaryID: primaryOverride, display: display)
    }

    private func arrange(_ layout: LayoutID?) {
        menu.cancelTracking()
        guard let layout else {
            run(.arrange)
            return
        }
        run(.layout(layout))
    }

    private func hover(_ layout: LayoutID?) {
        card.hoveredLayout = layout
        card.hoverPreview = layout.flatMap {
            app.coordinator.preview(
                focusedID: focusedID, primaryID: primaryOverride, display: display, action: .layout($0))
        }
    }

    private func pickPrimary(_ id: WindowID, arrangeNow: Bool = false) {
        primaryOverride = id
        if arrangeNow {
            arrange(.masterStack)
            return
        }
        card.preview = app.coordinator.preview(
            focusedID: focusedID, primaryID: id, display: display, action: .layout(.masterStack))
        card.hoverPreview = nil
        card.hoveredLayout = nil
    }

    // MARK: Item helpers

    private func commandItem(_ command: Command, perform: @escaping @MainActor () -> Void) -> NSMenuItem {
        let entry = item(command.title, perform: perform)
        // A static copy: the menu is rebuilt on every open, and setShortcut(for:)
        // would register a NotificationCenter observer per item that is never removed.
        entry.setShortcut(KeyboardShortcuts.getShortcut(for: command.shortcutName))
        return entry
    }

    private func actionItem(_ action: WindowAction) -> NSMenuItem {
        let entry = commandItem(.window(action)) { [weak self] in self?.app.perform(.window(action)) }
        entry.image = ActionIcons.image(for: action)
        return entry
    }

    /// "Always Place <App>" submenu: a per-app rule (Settings › Apps › Rules).
    private func ruleMenu(for bundleID: String, name: String) -> NSMenuItem {
        let current = app.settings.appRules[bundleID].flatMap(WindowAction.init(rawValue:))
        let parent = NSMenuItem(title: "Always Place \(name)", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let none = item("Not Set") { [weak self] in self?.app.setRule(nil, bundleID: bundleID) }
        none.state = current == nil ? .on : .off
        sub.addItem(none)
        sub.addItem(.separator())
        for action in WindowAction.ruleChoices {
            let i = item(action.title) { [weak self] in self?.app.setRule(action, bundleID: bundleID) }
            i.state = current == action ? .on : .off
            sub.addItem(i)
        }
        parent.submenu = sub
        return parent
    }

    private func item(_ title: String, symbol: String? = nil, perform: @escaping @MainActor () -> Void) -> NSMenuItem {
        let entry = ClosureMenuItem(title: title, perform: perform)
        if let symbol { entry.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return entry
    }

    private func submenu(_ title: String, _ sub: NSMenu) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        parent.submenu = sub
        return parent
    }

    private func frontmostApp() -> (name: String, bundleID: String)? {
        let own = ProcessInfo.processInfo.processIdentifier
        var running = NSWorkspace.shared.frontmostApplication
        if running?.processIdentifier == own, let pid = FrontmostAppTracker.shared.lastExternalPID {
            running = NSRunningApplication(processIdentifier: pid)
        }
        guard let running, running.processIdentifier != own, let bundleID = running.bundleIdentifier else { return nil }
        return (running.localizedName ?? bundleID, bundleID)
    }

    private func autoPrimaryName(_ p: ArrangeCoordinator.Preview) -> String {
        p.primaryID.flatMap { p.appNames[$0] } ?? "active window"
    }

    private func windowLabel(_ id: WindowID, _ p: ArrangeCoordinator.Preview) -> String {
        let app = p.appNames[id] ?? "Window"
        let title = (p.titles[id] ?? "").trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, title != app else { return app }
        return "\(app) – \(title.count > 40 ? String(title.prefix(40)) + "…" : title)"
    }
}

/// NSMenuItem that runs a closure. Menu actions arrive on the main thread.
@MainActor
final class ClosureMenuItem: NSMenuItem {
    private let perform: @MainActor () -> Void

    init(title: String, perform: @escaping @MainActor () -> Void) {
        self.perform = perform
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func fire() {
        perform()
    }
}
