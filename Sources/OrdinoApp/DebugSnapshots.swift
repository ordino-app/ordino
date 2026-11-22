#if DEBUG
    import AppKit
    import SwiftUI

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
                NSApp.terminate(nil)
            }
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
            guard let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return }
            content.cacheDisplay(in: content.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: file)
            window.orderOut(nil)
        }
    }
#endif
