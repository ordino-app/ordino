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
        button.image = Self.icon(style: app.settings.menuBarIconStyle, updateWaiting: updateWaiting)
        button.setAccessibilityLabel(updateWaiting ? "ordino, update available" : "ordino")
    }

    /// The menu bar icon. Monochrome is a template image macOS tints; the colour styles draw the brand mark
    /// (terracotta primary tile, graphite or off-white stack). The automatic one is drawn on demand, so it
    /// follows the menu bar's appearance whenever it changes (light/dark mode, wallpaper tinting).
    static func icon(style: MenuBarIconStyle, updateWaiting: Bool) -> NSImage? {
        if style == .monochrome {
            var image = Bundle.main.image(forResource: "MenuBarIcon")
            if image == nil || updateWaiting {
                image = NSImage(
                    systemSymbolName: updateWaiting ? "rectangle.split.2x2.fill" : "rectangle.split.2x2",
                    accessibilityDescription: "ordino")
            }
            image?.isTemplate = true
            return image
        }
        let terracotta = NSColor(srgbRed: 0.851, green: 0.396, blue: 0.231, alpha: 1)
        let graphite = NSColor(srgbRed: 0.169, green: 0.176, blue: 0.192, alpha: 1)
        let offWhite = NSColor(srgbRed: 0.929, green: 0.918, blue: 0.894, alpha: 1)
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            let dark: Bool =
                switch style {
                case .colorDark: true
                case .colorLight: false
                default: NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                }
            let s = 15.0 / 48
            let x0 = (rect.width - 48 * s) / 2
            let y0 = (rect.height - 48 * s) / 2
            func tile(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ color: NSColor) {
                color.setFill()
                NSBezierPath(
                    roundedRect: NSRect(x: x0 + x * s, y: y0 + y * s, width: w * s, height: h * s),
                    xRadius: 4.3 * s, yRadius: 4.3 * s
                ).fill()
            }
            let stack = dark ? offWhite : graphite
            tile(0, 0, 24.6, 48, terracotta)
            tile(30, 0, 18, 24.6, stack)
            tile(30, 30, 18, 18, stack)
            if updateWaiting {
                // A small dot on the top tile: an update is ready.
                NSColor.systemBlue.setFill()
                NSBezierPath(ovalIn: NSRect(x: rect.width - 6, y: 0, width: 6, height: 6)).fill()
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "ordino"
        return image
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

        let sections = app.settings.menuSections
        menu.addItem(.separator())
        if sections.contains(.windowActions) {
            let moves = NSMenu()
            moves.autoenablesItems = false
            addWindowActions(to: moves, enabled: trusted)
            let parent = submenu("Move Window", moves)
            parent.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
            parent.isEnabled = trusted
            menu.addItem(parent)
        }
        if sections.contains(.workspaces) { menu.addItem(workspacesMenu(enabled: trusted)) }
        if sections.contains(.customLayouts), !app.settings.customLayouts.isEmpty {
            menu.addItem(customLayoutsMenu(enabled: trusted))
        }
        if sections.contains(.appOptions), let frontmost = frontmostApp() {
            let options = NSMenu()
            let ignore = item("Ignore \(frontmost.name)") { [weak self] in
                self?.app.toggleIgnored(bundleID: frontmost.bundleID)
            }
            ignore.state = app.settings.ignoredApps.contains(frontmost.bundleID) ? .on : .off
            options.addItem(ignore)
            options.addItem(ruleMenu(for: frontmost.bundleID, name: "Always Place"))
            let parent = submenu(frontmost.name, options)
            parent.image = NSImage(systemSymbolName: "app.badge", accessibilityDescription: nil)
            menu.addItem(parent)
        }
        if menu.items.last?.isSeparatorItem == false { menu.addItem(.separator()) }

        let settings = item("Settings…") { [weak self] in self?.app.showSettings() }
        settings.keyEquivalent = ","
        settings.keyEquivalentModifierMask = .command
        menu.addItem(settings)
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
            if app.settings.menuSections.contains(.layoutOptions) { menu.addItem(submenu("Layout", layouts)) }

            // Primary window: only meaningful for Master + Stack.
            if app.settings.menuSections.contains(.layoutOptions), preview.plan.candidates.contains(.masterStack),
                preview.windowIDs.count > 1
            {
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

        if app.settings.menuSections.contains(.layoutOptions) {
            menu.addItem(commandItem(.rotate) { [weak self] in self?.run(.rotate) })
        }
        let undo = commandItem(.undo) { [weak self] in self?.app.undo() }
        undo.isEnabled = app.coordinator.canUndo
        menu.addItem(undo)
    }

    private func addWindowActions(to target: NSMenu, enabled: Bool) {
        let sections: [[WindowAction]] = [
            [.leftHalf, .rightHalf, .centerHalf, .topHalf, .bottomHalf],
            [.topLeft, .topRight, .bottomLeft, .bottomRight],
            [.firstThird, .centerThird, .lastThird, .firstTwoThirds, .centerTwoThirds, .lastTwoThirds],
            [.maximize, .almostMaximize, .maximizeHeight, .larger, .smaller, .center, .restore],
            [.nextDisplay, .previousDisplay],
        ]
        let multipleDisplays = Displays.all().count > 1
        for (index, section) in sections.enumerated() {
            if index > 0 { target.addItem(.separator()) }
            for action in section {
                let entry = actionItem(action)
                let needsDisplays = action == .nextDisplay || action == .previousDisplay
                entry.isEnabled = enabled && (!needsDisplays || multipleDisplays)
                target.addItem(entry)
            }
        }
        target.addItem(.separator())
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
            target.addItem(parent)
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

    /// "Custom Layouts" submenu: the user's grids (Settings › Layouts).
    private func customLayoutsMenu(enabled: Bool) -> NSMenuItem {
        let parent = NSMenuItem(title: "Custom Layouts", action: nil, keyEquivalent: "")
        parent.image = NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: nil)
        let sub = NSMenu()
        for layout in app.settings.customLayouts {
            let i = item("\(layout.name)  (\(layout.columns)×\(layout.rows))") { [weak self] in
                self?.app.applyCustomLayout(layout.id)
            }
            i.isEnabled = enabled
            if let shortcut = KeyboardShortcuts.getShortcut(for: layout.shortcutName) { i.setShortcut(shortcut) }
            sub.addItem(i)
        }
        sub.addItem(.separator())
        sub.addItem(item("Manage Custom Layouts…") { [weak self] in self?.app.showSettings(pane: .layouts) })
        parent.submenu = sub
        return parent
    }

    /// "Workspaces" submenu: apply a saved workspace, or save the current display as one.
    private func workspacesMenu(enabled: Bool) -> NSMenuItem {
        let parent = NSMenuItem(title: "Workspaces", action: nil, keyEquivalent: "")
        parent.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil)
        let sub = NSMenu()
        for ws in app.settings.workspaces {
            let i = item(ws.name) { [weak self] in self?.app.applyWorkspace(ws.id) }
            i.toolTip = ws.summary
            i.isEnabled = enabled
            if let shortcut = KeyboardShortcuts.getShortcut(for: ws.shortcutName) { i.setShortcut(shortcut) }
            sub.addItem(i)
        }
        if !app.settings.workspaces.isEmpty { sub.addItem(.separator()) }
        let save = item("Save Current Layout as Workspace…") { [weak self] in self?.app.saveWorkspace() }
        save.isEnabled = enabled
        sub.addItem(save)
        sub.addItem(item("Manage Workspaces…") { [weak self] in self?.app.showSettings(pane: .layouts) })
        parent.submenu = sub
        return parent
    }

    /// "Always Place <App>" submenu: a per-app rule (Settings › Apps › Rules).
    private func ruleMenu(for bundleID: String, name: String) -> NSMenuItem {
        let current = app.settings.appRules[bundleID].flatMap(WindowAction.init(rawValue:))
        let parent = NSMenuItem(title: name, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let none = item("Not Set") { [weak self] in self?.app.setRule(nil, bundleID: bundleID) }
        none.state = current == nil ? .on : .off
        sub.addItem(none)
        sub.addItem(.separator())
        for action in WindowAction.ruleChoices {
            let i = item(action.title) { [weak self] in self?.app.setRule(action, bundleID: bundleID) }
            i.image = ActionIcons.image(for: action)
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
