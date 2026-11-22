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

    /// One line under the pane's title.
    var subtitle: String {
        switch self {
        case .general: "Startup, which display to arrange, and feedback."
        case .layouts: "Spacing, the primary window and how many windows fit."
        case .shortcuts: "Every action, on the keys you choose."
        case .apps: "Apps that always lead, and apps ordino leaves alone."
        case .updates: "Signed updates, delivered quietly."
        case .about: "Version, diagnostics and credits."
        }
    }

    /// Monochrome outline icon for the sidebar.
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .layouts: "rectangle.split.2x2"
        case .shortcuts: "keyboard"
        case .apps: "square.stack.3d.up"
        case .updates: "arrow.down.circle"
        case .about: "info.circle"
        }
    }
}

/// The ordino mark on its 48 grid (see brand/README.md).
struct BrandMark: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 48
        let x0 = rect.midX - 24 * s
        let y0 = rect.midY - 24 * s
        func tile(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: x0 + x * s, y: y0 + y * s, width: w * s, height: h * s)
        }
        var path = Path()
        let r = CGSize(width: 4.3 * s, height: 4.3 * s)
        path.addRoundedRect(in: tile(0, 0, 24.6, 48), cornerSize: r, style: .continuous)
        path.addRoundedRect(in: tile(30, 0, 18, 24.6), cornerSize: r, style: .continuous)
        path.addRoundedRect(in: tile(30, 30, 18, 18), cornerSize: r, style: .continuous)
        return path
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
                    Label(pane.title, systemImage: pane.symbol)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 240)
            .safeAreaInset(edge: .bottom) { SidebarFooter(app: app) }
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

/// Bottom of the sidebar: the ordino mark, the version, and Quit.
struct SidebarFooter: View {
    let app: AppDelegate

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                BrandMarkColored().frame(width: 22, height: 22)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("ordino").font(.system(size: 12, weight: .semibold))
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.primary.opacity(0.07)))
            }
            .buttonStyle(.plain)
            .help("Quit ordino")
            .accessibilityLabel("Quit ordino")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

/// The ordino mark in its brand colours: terracotta primary tile, neutral stack.
struct BrandMarkColored: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height) / 48
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 4.3 * s, style: .continuous)
                    .fill(Color(red: 0.85, green: 0.40, blue: 0.23))
                    .frame(width: 24.6 * s, height: 48 * s)
                RoundedRectangle(cornerRadius: 4.3 * s, style: .continuous)
                    .fill(Color.primary.opacity(0.85))
                    .frame(width: 18 * s, height: 24.6 * s)
                    .offset(x: 30 * s)
                RoundedRectangle(cornerRadius: 4.3 * s, style: .continuous)
                    .fill(Color.primary.opacity(0.85))
                    .frame(width: 18 * s, height: 18 * s)
                    .offset(x: 30 * s, y: 30 * s)
            }
        }
    }
}
