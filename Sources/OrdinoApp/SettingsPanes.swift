import AppKit
import ArrangeCore
import Combine
import Geometry
import KeyboardShortcuts
import LayoutEngine
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
import WindowKit

// MARK: - General

struct GeneralPane: View {
    let app: AppDelegate
    @Bindable var settings: Settings
    @State private var trusted = AccessibilityPermission.isTrusted
    private let poll = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                Toggle("Launch ordino at login", isOn: $settings.launchAtLogin)
                if settings.launchAtLoginNeedsApproval {
                    LabeledContent("macOS needs your approval in Login Items.") {
                        Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                    }
                    .foregroundStyle(.orange)
                }
                Toggle("Show ordino in the menu bar", isOn: $settings.showMenuBarIcon)
            } footer: {
                if let error = settings.launchAtLoginError {
                    Footnote("Couldn't change launch at login: \(error)")
                } else if !settings.showMenuBarIcon {
                    Footnote("Open ordino again from Applications or Spotlight to get back to Settings.")
                }
            }

            Section("Arranging") {
                Picker("Arrange", selection: $settings.arrangeTarget) {
                    ForEach(ArrangeTarget.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Press the shortcut again to try the next layout", isOn: $settings.cycleOnRepeat)
            }

            Section("Feedback") {
                Toggle("Show a confirmation after arranging", isOn: $settings.showArrangeHUD)
                Toggle("Show a confirmation after window actions", isOn: $settings.showActionHUD)
            }

            Section {
                LabeledContent("Accessibility") {
                    if trusted {
                        Label("Allowed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Allow Access…") { app.showOnboarding() }
                    }
                }
            } header: {
                Text("Permissions")
            } footer: {
                Footnote(
                    "ordino uses Accessibility only to read window positions and move windows. It never records your screen."
                )
            }
        }
        .formStyle(.grouped)
        .onReceive(poll) { _ in trusted = AccessibilityPermission.isTrusted }
    }
}

// MARK: - Layouts

struct LayoutsPane: View {
    let app: AppDelegate
    @Bindable var settings: Settings
    @State private var confirmForget = false

    var body: some View {
        Form {
            Section {
                LayoutPreviewDiagram(gap: settings.gap, margin: settings.outerMargin, ratio: settings.masterRatio)
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .accessibilityHidden(true)
            }

            Section("Spacing") {
                SliderRow(title: "Gap between windows", value: $settings.gap, range: 0...32, step: 2, unit: "pt")
                SliderRow(
                    title: "Margin around the screen", value: $settings.outerMargin, range: 0...48, step: 2, unit: "pt")
            }

            Section("Master + Stack") {
                SliderRow(
                    title: "Primary window width", value: $settings.masterRatio, range: 0.3...0.8, step: 0.05,
                    format: { "\(Int(($0 * 100).rounded())) %" })
            }

            Section {
                Stepper(value: $settings.maxWindows, in: 2...16) {
                    LabeledContent("Windows per display", value: "\(settings.maxWindows)")
                }
                LabeledContent("Remembered layouts") {
                    Button("Forget…") { confirmForget = true }
                        .disabled(settings.preferredLayouts.isEmpty)
                }
            } header: {
                Text("Windows")
            } footer: {
                Footnote(
                    "Windows beyond the limit stay where they are. ordino remembers the layout you pick for each display and window count."
                )
            }

            Section {
                HStack {
                    Spacer()
                    Button("Restore Defaults") { settings.resetLayoutDefaults() }
                }
            }
            .listRowBackground(Color.clear)
        }
        .formStyle(.grouped)
        .confirmationDialog("Forget remembered layouts?", isPresented: $confirmForget) {
            Button("Forget Layouts", role: .destructive) { app.forgetRememberedLayouts() }
        } message: {
            Text("ordino goes back to its smart defaults for every display and window count.")
        }
    }
}

/// Live drawing of Master + Stack with the current spacing settings.
struct LayoutPreviewDiagram: View {
    let gap: Double
    let margin: Double
    let ratio: Double

    var body: some View {
        GeometryReader { geo in
            let screen = CGSize(width: 1440, height: 900)
            let scale = min(geo.size.width / screen.width, geo.size.height / screen.height)
            let size = CGSize(width: screen.width * scale, height: screen.height * scale)
            let origin = CGPoint(x: (geo.size.width - size.width) / 2, y: (geo.size.height - size.height) / 2)
            let rects = Self.slots(screen: screen, gap: gap, margin: margin, ratio: ratio)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.30), Color(white: 0.18)], startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: size.width, height: size.height)
                    .offset(x: origin.x, y: origin.y)
                ForEach(Array(rects.enumerated()), id: \.offset) { index, r in
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(index == 0 ? Color(red: 0.85, green: 0.40, blue: 0.23) : Color(white: 0.92))
                        .frame(width: max(1, r.w * scale), height: max(1, r.h * scale))
                        .offset(x: origin.x + r.x * scale, y: origin.y + r.y * scale)
                        .animation(.smooth(duration: 0.2), value: r)
                }
            }
        }
    }

    static func slots(screen: CGSize, gap: Double, margin: Double, ratio: Double) -> [Rect] {
        var prefs = LayoutPreferences()
        prefs.gap = gap
        prefs.outerPadding = .init(all: margin)
        prefs.masterRatio = ratio
        let area = Rect(x: 0, y: 0, w: screen.width, h: screen.height)
        let windows = (1...3).map { WindowInfo(id: WindowID($0), frame: area, isFocused: $0 == 1) }
        guard
            let plan = LayoutEngine().plan(
                LayoutContext(area: area, windows: windows, preferences: prefs), layout: .masterStack)
        else { return [] }
        return [1, 2, 3].compactMap { plan.frames[WindowID($0)] }
    }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var unit: String = ""
    var format: ((Double) -> String)?

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Slider(
                    value: Binding(
                        get: { value },
                        set: { value = min(range.upperBound, max(range.lowerBound, ($0 / step).rounded() * step)) }),
                    in: range
                )
                .frame(width: 180)
                .accessibilityLabel(title)
                .accessibilityValue(label)
                Text(label)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .trailing)
                    .accessibilityHidden(true)
            }
        }
    }

    private var label: String { format?(value) ?? "\(Int(value.rounded())) \(unit)" }
}

// MARK: - Shortcuts

struct ShortcutsPane: View {
    let app: AppDelegate
    @Bindable var settings: Settings
    @State private var pendingPreset: ShortcutPreset?
    @State private var confirmClear = false
    @State private var resetToken = 0

    private let sections: [(String, [WindowAction])] = [
        ("Halves", [.leftHalf, .rightHalf, .centerHalf, .topHalf, .bottomHalf]),
        ("Corners", [.topLeft, .topRight, .bottomLeft, .bottomRight]),
        ("Thirds", [.firstThird, .centerThird, .lastThird, .firstTwoThirds, .centerTwoThirds, .lastTwoThirds]),
        ("Fourths", [.firstFourth, .secondFourth, .thirdFourth, .lastFourth, .firstThreeFourths, .lastThreeFourths]),
        (
            "Sixths",
            [.topLeftSixth, .topCenterSixth, .topRightSixth, .bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth]
        ),
        ("Size", [.maximize, .almostMaximize, .maximizeHeight, .larger, .smaller, .restore]),
        ("Position", [.center, .moveLeft, .moveRight, .moveUp, .moveDown]),
        ("Displays", [.nextDisplay, .previousDisplay]),
    ]

    var body: some View {
        Form {
            Section {
                Picker(
                    "Window shortcuts",
                    selection: Binding(get: { settings.shortcutPreset }, set: { pendingPreset = $0 })
                ) {
                    ForEach(ShortcutPreset.allCases) { Text($0.title).tag($0) }
                }
                if let manager = app.conflictingWindowManager {
                    Label(
                        "\(manager) is running. Shortcuts that both apps use only work in one of them.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                    .font(.callout)
                }
            } footer: {
                Footnote("Click a shortcut to record a new one. Press Delete while recording to remove it.")
            }

            Section("Arrange") {
                ForEach(Command.arrangeCommands) { command in
                    ShortcutRow(title: command.title, icon: nil, name: command.shortcutName)
                }
            }

            ForEach(sections, id: \.0) { title, actions in
                Section(title) {
                    ForEach(actions) { action in
                        ShortcutRow(
                            title: action.title, icon: ActionIcons.image(for: action),
                            name: Command.window(action).shortcutName)
                    }
                }
            }

            Section {
                HStack {
                    Button("Clear Window Shortcuts…") { confirmClear = true }
                    Spacer()
                    Button("Reset Arrange Shortcuts") {
                        ShortcutPreset.applyArrangeDefaults()
                        resetToken += 1
                    }
                }
            }
            .listRowBackground(Color.clear)
        }
        .formStyle(.grouped)
        .id(resetToken)
        .confirmationDialog(
            "Replace window shortcuts?",
            isPresented: Binding(get: { pendingPreset != nil }, set: { if !$0 { pendingPreset = nil } })
        ) {
            if let preset = pendingPreset {
                Button("Use \(preset.title)") {
                    settings.shortcutPreset = preset
                    preset.apply()
                    resetToken += 1
                    pendingPreset = nil
                }
            }
        } message: {
            Text("Your custom window shortcuts are replaced. Arrange shortcuts stay as they are.")
        }
        .confirmationDialog("Clear all window shortcuts?", isPresented: $confirmClear) {
            Button("Clear Shortcuts", role: .destructive) {
                settings.shortcutPreset = .none
                ShortcutPreset.none.apply()
                resetToken += 1
            }
        } message: {
            Text("Window actions stay available from the menu.")
        }
    }
}

struct ShortcutRow: View {
    let title: String
    let icon: NSImage?
    let name: KeyboardShortcuts.Name

    var body: some View {
        LabeledContent {
            KeyboardShortcuts.Recorder(for: name)
        } label: {
            HStack(spacing: 8) {
                if let icon {
                    Image(nsImage: icon).foregroundStyle(.secondary).accessibilityHidden(true)
                }
                Text(title)
            }
        }
    }
}

// MARK: - Apps

struct AppsPane: View {
    @Bindable var settings: Settings

    var body: some View {
        Form {
            Section {
                AppList(
                    bundleIDs: $settings.primaryApps, reorderable: true,
                    emptyText: "No apps yet. The active window is primary.")
            } header: {
                Text("Always primary")
            } footer: {
                Footnote(
                    "With Master + Stack, the first of these apps that has a window on the display gets the large slot. Drag, or right-click, to change the order."
                )
            }

            Section {
                AppList(bundleIDs: $settings.ignoredApps, reorderable: false, emptyText: "No ignored apps.")
            } header: {
                Text("Ignored")
            } footer: {
                Footnote("ordino never moves windows of these apps, neither when arranging nor with window actions.")
            }
        }
        .formStyle(.grouped)
    }
}

struct AppList: View {
    @Binding var bundleIDs: [String]
    let reorderable: Bool
    let emptyText: String

    var body: some View {
        if bundleIDs.isEmpty {
            Text(emptyText).foregroundStyle(.secondary)
        }
        ForEach(bundleIDs, id: \.self) { bundleID in
            HStack(spacing: 10) {
                if reorderable {
                    Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary).accessibilityHidden(true)
                }
                AppLabel(bundleID: bundleID)
                Spacer()
                Button {
                    bundleIDs.removeAll { $0 == bundleID }
                } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove")
                .accessibilityLabel("Remove \(AppLabel.name(for: bundleID))")
            }
            .contextMenu {
                if reorderable {
                    Button("Move Up") { move(bundleID, by: -1) }.disabled(bundleIDs.first == bundleID)
                    Button("Move Down") { move(bundleID, by: 1) }.disabled(bundleIDs.last == bundleID)
                    Divider()
                }
                Button("Remove") { bundleIDs.removeAll { $0 == bundleID } }
            }
            .accessibilityElement(children: .combine)
            .accessibilityActions {
                if reorderable {
                    Button("Move Up") { move(bundleID, by: -1) }
                    Button("Move Down") { move(bundleID, by: 1) }
                }
                Button("Remove") { bundleIDs.removeAll { $0 == bundleID } }
            }
        }
        .onMove { from, to in if reorderable { bundleIDs.move(fromOffsets: from, toOffset: to) } }

        HStack {
            Menu("Add App") {
                let running = AppList.runningApps().filter { !bundleIDs.contains($0.bundleID) }
                if running.isEmpty { Text("No other apps are running") }
                ForEach(running, id: \.bundleID) { app in
                    Button(app.name) { bundleIDs.append(app.bundleID) }
                }
                Divider()
                Button("Choose…") { choose() }
            }
            .fixedSize()
            Spacer()
        }
    }

    private func move(_ bundleID: String, by offset: Int) {
        guard let i = bundleIDs.firstIndex(of: bundleID) else { return }
        let j = i + offset
        guard bundleIDs.indices.contains(j) else { return }
        bundleIDs.swapAt(i, j)
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier, !bundleIDs.contains(id) { bundleIDs.append(id) }
        }
    }

    static func runningApps() -> [(name: String, bundleID: String)] {
        let own = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let id = app.bundleIdentifier, id != own else { return nil }
                return (app.localizedName ?? id, id)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

struct AppLabel: View {
    let bundleID: String

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: Self.icon(for: bundleID))
                .resizable()
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            Text(Self.name(for: bundleID))
        }
    }

    static func name(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    static func icon(for bundleID: String) -> NSImage {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

// MARK: - Updates

struct UpdatesPane: View {
    let app: AppDelegate
    @Bindable var settings: Settings
    @State private var tick = 0

    var body: some View {
        let updater = app.updater
        Form {
            if updater.isAvailable {
                Section {
                    Toggle(
                        "Check for updates automatically",
                        isOn: Binding(
                            get: {
                                _ = tick
                                return updater.automaticallyChecks
                            },
                            set: {
                                updater.automaticallyChecks = $0
                                tick += 1
                            }))
                    Toggle(
                        "Download and install updates automatically",
                        isOn: Binding(
                            get: {
                                _ = tick
                                return updater.automaticallyDownloads
                            },
                            set: {
                                updater.automaticallyDownloads = $0
                                tick += 1
                            })
                    )
                    .disabled(!updater.automaticallyChecks)
                    // A beta build always follows the beta channel (see Updater.allowedChannels).
                    Toggle(
                        "Include beta versions",
                        isOn: Updater.isPrerelease ? .constant(true) : $settings.betaUpdates
                    )
                    .disabled(Updater.isPrerelease)
                    if Updater.isPrerelease {
                        Footnote("You're running a beta, so you get beta updates until the next stable release.")
                    }
                } footer: {
                    Footnote(
                        "Updates are signed; ordino refuses any update that isn't. Your Accessibility permission stays on."
                    )
                }
                Section {
                    LabeledContent("Current version", value: AboutPane.versionString)
                    LabeledContent("Last checked") {
                        Text(updater.lastCheck.map { $0.formatted(.relative(presentation: .named)) } ?? "Never")
                    }
                    HStack {
                        Spacer()
                        Button("Check Now") {
                            updater.checkForUpdates()
                            tick += 1
                        }
                        .disabled(!updater.canCheck)
                    }
                }
            } else {
                Section {
                    Label("Updates work in the installed app, not in development builds.", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - About

struct AboutPane: View {
    let app: AppDelegate
    @State private var copied = false

    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 96, height: 96)
                        .accessibilityHidden(true)
                    Text("ordino").font(.largeTitle.weight(.semibold))
                    Text("Every window, in its place.").foregroundStyle(.secondary)
                    Text("Version \(Self.versionString)").font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)

            Section("Support") {
                LabeledContent("Diagnostics") {
                    Button(copied ? "Copied" : "Copy Diagnostics") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(diagnostics(), forType: .string)
                        copied = true
                    }
                }
            }

            Section("Acknowledgements") {
                LabeledContent("Sparkle", value: "MIT License")
                LabeledContent("KeyboardShortcuts", value: "MIT License")
                LabeledContent("ordino", value: "MIT License · free")
            }
        }
        .formStyle(.grouped)
    }

    /// Facts a bug report needs, without window titles or other personal data.
    private func diagnostics() -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var arch = "unknown"
        #if arch(arm64)
            arch = "arm64"
        #elseif arch(x86_64)
            arch = "x86_64"
        #endif
        let displays = Displays.all().map { "\($0.name) \(Int($0.frame.w))x\(Int($0.frame.h))" }
        let settings = app.settings
        return """
            ordino \(Self.versionString)
            macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion) (\(arch))
            Accessibility: \(AccessibilityPermission.isTrusted ? "allowed" : "not allowed")
            Displays: \(displays.joined(separator: ", "))
            Arrange target: \(settings.arrangeTarget.rawValue), gap \(Int(settings.gap)), margin \(Int(settings.outerMargin)), \
            master \(Int(settings.masterRatio * 100))%, max \(settings.maxWindows)
            Shortcut preset: \(settings.shortcutPreset.rawValue)
            Other window manager running: \(app.conflictingWindowManager ?? "none")
            Ignored apps: \(settings.ignoredApps.count), always-primary apps: \(settings.primaryApps.count)
            """
    }
}

/// Section footer text, leading-aligned like System Settings.
struct Footnote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
