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
                            model: model, arrangeShortcut: "⌃⌥⌘A", onArrange: { _ in }, onHover: { _ in },
                            onPickPrimary: { _ in }
                        )
                        .background(.regularMaterial)
                        await render(
                            card, size: NSHostingView(rootView: card).fittingSize, appearance: appearance,
                            to: url.appendingPathComponent("menu-card-\(name)-\(suffix).png"))
                    }
                }
                NSApp.terminate(nil)
            }
        }

        /// A preview with real installed apps on the first display (for its wallpaper).
        private static func samplePreview(layout: LayoutID, count: Int) -> ArrangeCoordinator.Preview? {
            guard let display = Displays.all().first else { return nil }
            let apps: [(String, String)] = [
                ("Xcode", "com.apple.dt.Xcode"), ("Safari", "com.apple.Safari"), ("Notes", "com.apple.Notes"),
                ("Mail", "com.apple.mail"), ("Google Chrome", "com.google.Chrome"), ("Terminal", "com.apple.Terminal"),
                ("Calendar", "com.apple.iCal"),
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
            window.contentViewController = NSHostingController(rootView: view)
            window.setContentSize(size)
            window.orderBack(nil)
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
