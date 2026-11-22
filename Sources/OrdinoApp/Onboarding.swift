import AppKit
import KeyboardShortcuts
import SwiftUI
import WindowKit

/// Explains and requests the Accessibility permission, then closes itself
/// as soon as macOS reports that access was granted.
@MainActor
final class OnboardingController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var timer: Timer?
    private let model = OnboardingModel()
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        super.init()
    }

    /// The close button counts as "done" too: stop polling and hand back focus.
    func windowWillClose(_ notification: Notification) {
        guard window != nil else { return }
        timer?.invalidate()
        timer = nil
        window = nil
        onFinish()
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        window.center()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        startPolling()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.title = "Welcome to ordino"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(
            rootView: OnboardingView(
                model: model,
                openSettings: {
                    AccessibilityPermission.requestWithPrompt()
                    NSWorkspace.shared.open(AccessibilityPermission.settingsURL)
                },
                done: { [weak self] in self?.finish() }))
        return window
    }

    private func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let trusted = AccessibilityPermission.isTrusted
                if trusted != self.model.trusted { self.model.trusted = trusted }
            }
        }
    }

    private func finish() {
        window?.close()  // windowWillClose does the rest
    }
}

@MainActor
@Observable
final class OnboardingModel {
    var trusted = AccessibilityPermission.isTrusted
}

private struct OnboardingView: View {
    let model: OnboardingModel
    let openSettings: () -> Void
    let done: () -> Void
    @State private var showHelp = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "rectangle.split.2x2")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tint)
            Text("Every window, in its place.").font(.title.weight(.semibold))
            Text(
                "ordino arranges all windows on a display with one keystroke: ⌃⌥⌘A. Press it again to try the next layout."
            )
            .foregroundStyle(.secondary)

            if model.trusted {
                Label("Accessibility access granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.headline)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Try these").font(.headline)
                    TipRow(keys: Self.keys(.arrange, fallback: "⌃⌥⌘A"), text: "Arrange every window on the display")
                    TipRow(keys: Self.keys(.arrange, fallback: "⌃⌥⌘A") + " again", text: "Cycle to the next layout")
                    TipRow(keys: Self.keys(.undo, fallback: "⌃⌥⌘Z"), text: "Put the windows back")
                    TipRow(keys: "Drag", text: "Pull a window to a screen edge or up to the top for more layouts")
                }
                Text("Everything else is in the ordino menu in the menu bar: workspaces, custom layouts, app rules.")
                    .foregroundStyle(.secondary).font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Start using ordino", action: done).keyboardShortcut(.defaultAction).controlSize(.large)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Allow Accessibility access").font(.headline)
                    Text(
                        "macOS only lets apps move other apps' windows with this permission. ordino uses it only to read window positions and move windows. It doesn't record your screen or send anything off your Mac."
                    )
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Text("1. Click the button below.  2. Turn on ordino in the list.  3. Come back here.")
                    .font(.callout)
                Button("Open System Settings", action: openSettings)
                    .keyboardShortcut(.defaultAction).controlSize(.large)
                DisclosureGroup("It's switched on but ordino still asks", isExpanded: $showHelp) {
                    Text(
                        "macOS ties the permission to the app's signature. Remove ordino from the list with the minus button, add it again, then relaunch ordino. Development builds signed ad hoc need this after every rebuild."
                    )
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .font(.callout)
            }
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(width: 520, height: 420, alignment: .topLeading)
        .animation(reduceMotion ? nil : .default, value: model.trusted)
    }
}

extension OnboardingView {
    /// The shortcut the user has for a command, as shown in menus (e.g. "⌃⌥⌘A").
    fileprivate static func keys(_ command: Command, fallback: String) -> String {
        KeyboardShortcuts.getShortcut(for: command.shortcutName).map { "\($0)" } ?? fallback
    }
}

private struct TipRow: View {
    let keys: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(keys)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            Text(text).font(.callout)
        }
    }
}
