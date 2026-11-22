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
                ToggleRow(
                    symbol: "power", title: "Launch at login",
                    help: "Start ordino when you log in, so your shortcuts always work.",
                    isOn: $settings.launchAtLogin)
                if settings.launchAtLoginNeedsApproval {
                    SubGroup {
                        SettingRow(symbol: "exclamationmark.triangle", title: "Needs your approval in Login Items") {
                            Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                        }
                        .foregroundStyle(.orange)
                    }
                }
                ToggleRow(
                    symbol: "menubar.rectangle", title: "Show in the menu bar",
                    help: "When hidden, open ordino again from Applications or Spotlight to get back to Settings.",
                    isOn: $settings.showMenuBarIcon)
            } header: {
                SectionTitle("Startup", symbol: "sunrise")
            } footer: {
                if let error = settings.launchAtLoginError {
                    Footnote("Couldn't change launch at login: \(error)")
                }
            }

            Section {
                SettingRow(
                    symbol: "display", title: "Display to arrange",
                    help:
                        "Arrange works on one display at a time: the one under the pointer, or the one showing the window you're working in."
                ) {
                    Picker("Display to arrange", selection: $settings.arrangeTarget) {
                        ForEach(ArrangeTarget.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                ToggleRow(
                    symbol: "arrow.triangle.2.circlepath", title: "Press again for the next layout",
                    help:
                        "Pressing the arrange shortcut again within 2 seconds switches to the next layout for the same windows.",
                    isOn: $settings.cycleOnRepeat)
            } header: {
                SectionTitle("Arranging", symbol: "rectangle.split.2x2")
            }

            Section {
                ToggleRow(
                    symbol: "checkmark.bubble", title: "Confirm arranging",
                    help:
                        "A short message near the top of the screen: how many windows, which layout, and how to undo.",
                    isOn: $settings.showArrangeHUD)
                ToggleRow(
                    symbol: "text.bubble", title: "Confirm window actions",
                    help:
                        "Also show a message after single-window actions like Left Half or Maximize. Problems are always shown.",
                    isOn: $settings.showActionHUD)
            } header: {
                SectionTitle("Feedback", symbol: "bell")
            }

            Section {
                ToggleRow(
                    symbol: "display.2", title: "Re-arrange when displays change",
                    help:
                        "After you connect or disconnect a monitor, ordino puts the windows on each display you arranged before back into that display's last layout.",
                    isOn: $settings.rearrangeOnDisplayChange)
                ToggleRow(
                    symbol: "hand.point.up.left", title: "Snap windows dragged to the screen edge",
                    help:
                        "Drag a window to the left or right edge for a half, to the top for full screen, or into a corner for a quarter. Hold ⌘ to drag without snapping. Off while another window manager is running.",
                    isOn: $settings.snapOnDrag)
                if settings.snapOnDrag && DragSnapController.systemTilingEnabled {
                    HStack(alignment: .firstTextBaseline) {
                        Text(
                            "macOS tiles windows dragged to the screen edge itself, so ordino leaves those drags alone. To use ordino's snapping, turn off \u{201C}Drag windows to screen edges to tile\u{201D} and \u{201C}Drag windows to menu bar to fill screen\u{201D}."
                        )
                        .font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Desktop & Dock…") {
                            NSWorkspace.shared.open(
                                URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!)
                        }
                    }
                }
            } header: {
                SectionTitle("Displays and dragging", symbol: "display")
            }

            Section {
                SettingRow(
                    symbol: "hand.raised", title: "Accessibility",
                    help:
                        "ordino uses Accessibility only to read window positions and move windows. It never records your screen, and nothing leaves your Mac."
                ) {
                    if trusted {
                        Label("Allowed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Allow Access…") { app.showOnboarding() }
                    }
                }
            } header: {
                SectionTitle("Permissions", symbol: "lock")
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
                    .accessibilityHidden(true)
            }

            Section {
                SliderRow(
                    symbol: "arrow.left.and.right", title: "Gap between windows",
                    help: "Space between windows that sit side by side.",
                    value: $settings.gap, range: 0...32, step: 2, unit: "pt")
                SliderRow(
                    symbol: "rectangle.dashed", title: "Margin around the screen",
                    help: "Space between the windows and the edges of the screen, menu bar and Dock.",
                    value: $settings.outerMargin, range: 0...48, step: 2, unit: "pt")
            } header: {
                SectionTitle("Spacing", symbol: "square.dashed")
            }

            Section {
                SliderRow(
                    symbol: "sidebar.left", title: "Primary window width",
                    help:
                        "How much of the screen the primary window takes in Master + Stack. The others share the rest.",
                    value: $settings.masterRatio, range: 0.3...0.8, step: 0.05,
                    format: { "\(Int(($0 * 100).rounded())) %" })
            } header: {
                SectionTitle("Master + Stack", symbol: "sidebar.left")
            }

            Section {
                SettingRow(
                    symbol: "square.grid.3x3", title: "Windows per display",
                    help: "Windows beyond the limit stay where they are, so very busy screens stay usable."
                ) {
                    Stepper("\(settings.maxWindows)", value: $settings.maxWindows, in: 2...16)
                        .monospacedDigit()
                        .fixedSize()
                }
                SettingRow(
                    symbol: "memories", title: "Remembered layouts",
                    help: "When you switch to another layout, ordino remembers it for that display and window count."
                ) {
                    Button("Forget…") { confirmForget = true }
                        .disabled(settings.preferredLayouts.isEmpty)
                }
            } header: {
                SectionTitle("Windows", symbol: "macwindow.on.rectangle")
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
                    // A visible seam even at a 0 pt gap, so the tiles never fuse.
                    let rect = CGRect(
                        x: origin.x + r.x * scale, y: origin.y + r.y * scale, width: r.w * scale, height: r.h * scale
                    )
                    .insetBy(dx: 2, dy: 2)
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(index == 0 ? Color(red: 0.85, green: 0.40, blue: 0.23) : Color(white: 0.92))
                        .frame(width: max(1, rect.width), height: max(1, rect.height))
                        .offset(x: rect.minX, y: rect.minY)
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
    var symbol: String = "slider.horizontal.3"
    let title: String
    var help: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var unit: String = ""
    var format: ((Double) -> String)?

    var body: some View {
        SettingRow(symbol: symbol, title: title, help: help) {
            HStack(spacing: 10) {
                Slider(
                    value: Binding(
                        get: { value },
                        set: { value = min(range.upperBound, max(range.lowerBound, ($0 / step).rounded() * step)) }),
                    in: range
                )
                .frame(width: 160)
                .accessibilityLabel(title)
                .accessibilityValue(label)
                Text(label)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
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

    static let sectionSymbols: [String: String] = [
        "Halves": "rectangle.lefthalf.filled", "Corners": "square.split.2x2", "Thirds": "rectangle.split.3x1",
        "Fourths": "rectangle.split.3x1", "Sixths": "square.grid.3x2", "Size": "arrow.up.left.and.arrow.down.right",
        "Position": "arrow.up.and.down.and.arrow.left.and.right", "Displays": "display.2",
    ]

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

            Section {
                ForEach(Command.arrangeCommands) { command in
                    ShortcutRow(title: command.title, icon: nil, name: command.shortcutName)
                }
            } header: {
                SectionTitle("Arrange", symbol: "rectangle.split.2x2")
            }

            ForEach(sections, id: \.0) { title, actions in
                Section {
                    ForEach(actions) { action in
                        ShortcutRow(
                            title: action.title, icon: ActionIcons.image(for: action),
                            name: Command.window(action).shortcutName)
                    }
                } header: {
                    SectionTitle(title, symbol: Self.sectionSymbols[title] ?? "macwindow")
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
    private func ruleBinding(_ bundleID: String) -> Binding<String> {
        Binding(
            get: { settings.appRules[bundleID] ?? WindowAction.leftHalf.rawValue },
            set: { settings.appRules[bundleID] = $0 })
    }

    @Bindable var settings: Settings

    var body: some View {
        Form {
            Section {
                AppList(
                    bundleIDs: $settings.primaryApps, reorderable: true,
                    emptyText: "No apps yet. The active window is primary.")
            } header: {
                SectionTitle("Always primary", symbol: "star")
            } footer: {
                Footnote(
                    "With Master + Stack, the first of these apps that has a window on the display gets the large slot. Drag, or right-click, to change the order."
                )
            }

            Section {
                AppList(bundleIDs: $settings.ignoredApps, reorderable: false, emptyText: "No ignored apps.")
            } header: {
                SectionTitle("Ignored", symbol: "eye.slash")
            } footer: {
                Footnote("ordino never moves windows of these apps, neither when arranging nor with window actions.")
            }

            Section {
                if settings.appRules.isEmpty {
                    Text("No rules.").foregroundStyle(.secondary)
                }
                ForEach(settings.appRules.keys.sorted(), id: \.self) { bundleID in
                    HStack {
                        AppLabel(bundleID: bundleID)
                        Spacer()
                        Picker("Place", selection: ruleBinding(bundleID)) {
                            ForEach(WindowAction.ruleChoices) { Text($0.title).tag($0.rawValue) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        Button {
                            settings.appRules[bundleID] = nil
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove the rule for \(AppLabel.name(for: bundleID))")
                    }
                }
            } header: {
                SectionTitle("Rules", symbol: "pin")
            } footer: {
                Footnote(
                    "Windows of these apps always go to their place and are left out of layouts. Add a rule from the menu bar: Always Place <app>."
                )
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
                    ToggleRow(
                        symbol: "clock.arrow.circlepath", title: "Check automatically",
                        help: "ordino looks for a new version once a day.",
                        isOn: Binding(
                            get: {
                                _ = tick
                                return updater.automaticallyChecks
                            },
                            set: {
                                updater.automaticallyChecks = $0
                                tick += 1
                            }))
                    if updater.automaticallyChecks {
                        SubGroup {
                            ToggleRow(
                                symbol: "arrow.down.to.line", title: "Download and install automatically",
                                help: "Updates install when you quit ordino. Without this, ordino asks first.",
                                isOn: Binding(
                                    get: {
                                        _ = tick
                                        return updater.automaticallyDownloads
                                    },
                                    set: {
                                        updater.automaticallyDownloads = $0
                                        tick += 1
                                    }))
                        }
                    }
                    // A beta build always follows the beta channel (see Updater.allowedChannels).
                    ToggleRow(
                        symbol: "testtube.2", title: "Include beta versions",
                        help: Updater.isPrerelease
                            ? "You're running a beta, so you get beta updates until the next stable release."
                            : "Get new features earlier. Betas are tested, but may have rough edges.",
                        isOn: Updater.isPrerelease ? .constant(true) : $settings.betaUpdates
                    )
                    .disabled(Updater.isPrerelease)
                } header: {
                    SectionTitle("Updates", symbol: "arrow.down.circle")
                } footer: {
                    Footnote("Every update is signed, and ordino refuses one that isn't. Accessibility stays allowed.")
                }
                Section {
                    SettingRow(symbol: "shippingbox", title: "Version") {
                        Text(AboutPane.versionString).foregroundStyle(.secondary)
                    }
                    SettingRow(symbol: "clock", title: "Last checked") {
                        Text(updater.lastCheck.map { $0.formatted(.relative(presentation: .named)) } ?? "Never")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Spacer()
                        Button("Check Now") {
                            updater.checkForUpdates()
                            tick += 1
                        }
                        .disabled(!updater.canCheck)
                    }
                } header: {
                    SectionTitle("This Mac", symbol: "laptopcomputer")
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

            Section {
                SettingRow(
                    symbol: "chevron.left.forwardslash.chevron.right", title: "GitHub",
                    help: "Made by xsugra. Follow along or say hello on GitHub."
                ) {
                    Link("github.com/xsugra", destination: AuthorLinks.github)
                }
                if let coffee = AuthorLinks.buyMeACoffee {
                    SettingRow(
                        symbol: "cup.and.saucer", title: "Buy me a coffee",
                        help: "ordino is free. If it saves you time, a coffee keeps it going."
                    ) {
                        Link("buymeacoffee.com/xsugra", destination: coffee)
                    }
                }
            } header: {
                SectionTitle("Author", symbol: "person")
            }

            Section {
                LabeledContent("Diagnostics") {
                    Button(copied ? "Copied" : "Copy Diagnostics") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(diagnostics(), forType: .string)
                        copied = true
                    }
                }
            } header: {
                SectionTitle("Support", symbol: "lifepreserver")
            }

            Section {
                LabeledContent("Sparkle", value: "MIT License")
                LabeledContent("KeyboardShortcuts", value: "MIT License")
                LabeledContent("ordino", value: "MIT License · free")
                if let licenses = Bundle.main.url(forResource: "Licenses", withExtension: "txt") {
                    Button("View Licenses…") { NSWorkspace.shared.open(licenses) }
                }
            } header: {
                SectionTitle("Acknowledgements", symbol: "heart")
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

/// Where people can find the author. Set `buyMeACoffee` once the profile exists.
enum AuthorLinks {
    static let github = URL(string: "https://github.com/xsugra")!
    static let buyMeACoffee: URL? = URL(string: "https://buymeacoffee.com/xsugra")
}
