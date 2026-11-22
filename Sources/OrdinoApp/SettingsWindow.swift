import AppKit
import SwiftUI
import WindowKit

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, layouts, shortcuts, apps, updates, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .layouts: "Layouts"
        case .shortcuts: "Shortcuts"
        case .apps: "Apps"
        case .updates: "Updates"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .layouts: "rectangle.split.2x2"
        case .shortcuts: "command"
        case .apps: "app.badge.checkmark"
        case .updates: "arrow.down.circle"
        case .about: "info.circle"
        }
    }

    /// Icon tile colour, like System Settings.
    var tint: Color {
        switch self {
        case .general: .gray
        case .layouts: Color(red: 0.85, green: 0.40, blue: 0.23)
        case .shortcuts: .indigo
        case .apps: .blue
        case .updates: .green
        case .about: .secondary
        }
    }
}

@MainActor
@Observable
final class SettingsNavigation {
    var pane: SettingsPane = .general
}

/// The Settings window. ordino is a menu bar app, so while Settings is open it
/// becomes a regular app (Dock icon, ⌘-Tab) and goes back to accessory on close.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private unowned let app: AppDelegate
    private var window: NSWindow?
    private let navigation = SettingsNavigation()

    init(app: AppDelegate) {
        self.app = app
    }

    func show(pane: SettingsPane) {
        navigation.pane = pane
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Stay a regular app while another ordino window (Sparkle's update
        // dialog, onboarding) is still open; otherwise go back to the menu bar
        // and give focus to the app the user was working in.
        let closing = notification.object as? NSWindow
        let othersOpen = NSApp.windows.contains { $0 !== closing && $0.isVisible && $0.canBecomeMain }
        guard !othersOpen else { return }
        NSApp.setActivationPolicy(.accessory)
        if let pid = FrontmostAppTracker.shared.lastExternalPID {
            NSRunningApplication(processIdentifier: pid)?.activate()
        }
    }

    private func makeWindow() -> NSWindow {
        let root = SettingsView(app: app, navigation: navigation)
        let controller = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: controller)
        window.title = "ordino Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.setContentSize(NSSize(width: 760, height: 560))
        window.contentMinSize = NSSize(width: 680, height: 460)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName("ordinoSettings")
        return window
    }
}

struct SettingsView: View {
    let app: AppDelegate
    @Bindable var navigation: SettingsNavigation

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: Binding($navigation.pane)) { pane in
                NavigationLink(value: pane) {
                    Label {
                        Text(pane.title)
                    } icon: {
                        Image(systemName: pane.symbol)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(pane.tint.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 240)
        } detail: {
            Group {
                switch navigation.pane {
                case .general: GeneralPane(app: app, settings: app.settings)
                case .layouts: LayoutsPane(app: app, settings: app.settings)
                case .shortcuts: ShortcutsPane(app: app, settings: app.settings)
                case .apps: AppsPane(settings: app.settings)
                case .updates: UpdatesPane(app: app, settings: app.settings)
                case .about: AboutPane(app: app)
                }
            }
            .navigationTitle(navigation.pane.title)
        }
    }
}
