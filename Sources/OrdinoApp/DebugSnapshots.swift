#if DEBUG
    import AppKit
    import ArrangeCore
    import Geometry
    import LayoutEngine
    import SwiftUI
    import WindowKit

    /// Development aid: renders every Settings pane offscreen to PNG files and quits.
    ///   open build/ordino.app --args -ordinoSnapshotDir /path/to/dir
    @MainActor
    enum DebugSnapshots {
        static func runIfRequested(app: AppDelegate) {
            guard let dir = UserDefaults.standard.string(forKey: "ordinoSnapshotDir") else { return }
            let url = URL(fileURLWithPath: dir, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            Task { @MainActor in
                for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                    for pane in SettingsPane.allCases {
                        let navigation = SettingsNavigation()
                        navigation.pane = pane
                        let view = SettingsView(app: app, navigation: navigation)
                        let suffix = appearance == .aqua ? "light" : "dark"
                        await render(
                            view, size: NSSize(width: 760, height: 620), appearance: appearance,
                            to: url.appendingPathComponent("settings-\(pane.rawValue)-\(suffix).png"))
                    }
                }
                for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                    let suffix = appearance == .aqua ? "light" : "dark"
                    for (name, layout, count) in [("3", LayoutID.masterStack, 3), ("7", .grid, 7)] {
                        let model = MenuCardModel()
                        model.preview = samplePreview(layout: layout, count: count)
                        let card = MenuCard(
                            model: model, arrangeShortcut: "⌥⌘A", onArrange: { _ in }, onHover: { _ in },
                            onPickPrimary: { _ in }
                        )
                        .background(.regularMaterial)
                        await render(
                            card, size: NSHostingView(rootView: card).fittingSize, appearance: appearance,
                            to: url.appendingPathComponent("menu-card-\(name)-\(suffix).png"))
                    }
                }
                await renderFeatureShots(app: app, to: url)
                NSApp.terminate(nil)
            }
        }

        /// Long Settings panes with sample content (custom layouts, workspaces, menu options) and the snap bar,
        /// for the website. The user's own settings are put back afterwards.
        private static func renderFeatureShots(app: AppDelegate, to url: URL) async {
            let s = app.settings
            let saved = (s.customLayouts, s.workspaces, s.menuSections, s.menuBarIconStyle)
            s.customLayouts = [
                CustomLayout(name: "3 Columns", columns: 3, rows: 1),
                CustomLayout(name: "2 × 2 Grid", columns: 2, rows: 2),
            ]
            s.workspaces = [
                Workspace(
                    name: "Coding",
                    slots: [
                        .init(bundleID: "sample.editor", appName: "Code Editor", x: 0, y: 0, w: 0.6, h: 1),
                        .init(bundleID: "sample.browser", appName: "Browser", x: 0.6, y: 0, w: 0.4, h: 0.5),
                        .init(bundleID: "sample.terminal", appName: "Terminal", x: 0.6, y: 0.5, w: 0.4, h: 0.5),
                    ]),
                Workspace(
                    name: "Writing",
                    slots: [
                        .init(bundleID: "sample.notes", appName: "Notes", x: 0, y: 0, w: 0.5, h: 1),
                        .init(bundleID: "sample.browser", appName: "Browser", x: 0.5, y: 0, w: 0.5, h: 1),
                    ]),
            ]
            s.menuSections = MenuSection.defaults
            s.menuBarIconStyle = .colorAutomatic
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let suffix = appearance == .aqua ? "light" : "dark"
                for pane in [SettingsPane.general, .layouts] {
                    let navigation = SettingsNavigation()
                    navigation.pane = pane
                    await render(
                        SettingsView(app: app, navigation: navigation), size: NSSize(width: 760, height: 1500),
                        appearance: appearance,
                        to: url.appendingPathComponent("settings-\(pane.rawValue)-tall-\(suffix).png"))
                }
                let model = SnapBarModel()
                model.hoveredGroup = 2
                model.hoveredAction = .firstTwoThirds
                await render(
                    SnapBarView(model: model).padding(24),
                    size: NSSize(width: SnapBar.size.w + 48, height: SnapBar.size.h + 48),
                    appearance: appearance, to: url.appendingPathComponent("snap-bar-\(suffix).png"))
            }
            (s.customLayouts, s.workspaces, s.menuSections, s.menuBarIconStyle) = saved
        }

        /// A preview with real installed apps on the first display (for its wallpaper).
        private static func samplePreview(layout: LayoutID, count: Int) -> ArrangeCoordinator.Preview? {
            guard let display = Displays.all().first else { return nil }
            // Neutral sample apps (no real app icons or names in published images).
            let apps: [(String, String)] = [
                ("Code Editor", "sample.editor"), ("Browser", "sample.browser"), ("Notes", "sample.notes"),
                ("Mail", "sample.mail"), ("Design", "sample.design"), ("Terminal", "sample.terminal"),
                ("Calendar", "sample.calendar"),
            ]
            // A neutral sample display: no personal wallpaper or monitor name in published images.
            let snapshot = DisplaySnapshot(
                id: "sample", name: "Built-in Retina Display", visibleFrame: display.visibleFrame)
            let windows = (0..<count).map {
                WindowInfo(id: WindowID($0 + 1), frame: display.visibleFrame, isFocused: $0 == 0)
            }
            var prefs = LayoutPreferences()
            prefs.gap = 10
            prefs.outerPadding = .init(all: 10)
            guard
                let plan = LayoutEngine().plan(
                    LayoutContext(area: display.visibleFrame, windows: windows, preferences: prefs), layout: layout)
            else { return nil }
            let ids = windows.map(\.id)
            return ArrangeCoordinator.Preview(
                display: snapshot, plan: plan,
                appNames: Dictionary(uniqueKeysWithValues: ids.map { ($0, apps[Int($0 - 1) % apps.count].0) }),
                bundleIDs: Dictionary(uniqueKeysWithValues: ids.map { ($0, apps[Int($0 - 1) % apps.count].1) }),
                titles: [:], windowIDs: ids, primaryID: 1)
        }

        private static func render<V: View>(_ view: V, size: NSSize, appearance: NSAppearance.Name, to file: URL) async
        {
            let window = NSWindow(
                contentRect: NSRect(origin: NSPoint(x: -20000, y: -20000), size: size),
                styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.appearance = NSAppearance(named: appearance)
            // Draw controls as in the active window (offscreen windows are never key, so toggles would look grey).
            window.contentViewController = NSHostingController(
                rootView: view.environment(\.controlActiveState, .key))
            window.setContentSize(size)
            // Controls draw as active only in the key window of the active app.
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(600))
            guard let content = window.contentView?.superview ?? window.contentView else { return }
            content.layoutSubtreeIfNeeded()
            // 2x pixels so screenshots stay sharp on Retina displays (website, docs).
            let bounds = content.bounds
            guard
                let rep = NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * 2), pixelsHigh: Int(bounds.height * 2),
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                    bytesPerRow: 0, bitsPerPixel: 0)
            else { return }
            rep.size = bounds.size
            content.cacheDisplay(in: bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: file)
            window.orderOut(nil)
        }
    }
#endif
