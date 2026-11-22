import Foundation
import LayoutEngine
import Observation
import ServiceManagement

/// Which display "Arrange" works on.
/// How the menu bar icon looks.
enum MenuBarIconStyle: String, CaseIterable, Identifiable, Sendable {
    /// One colour, drawn by macOS like other menu bar icons.
    case monochrome
    /// The brand colours; the two small tiles follow the menu bar (light or dark).
    case colorAutomatic
    /// The brand colours with dark small tiles, for a light menu bar.
    case colorLight
    /// The brand colours with light small tiles, for a dark menu bar.
    case colorDark

    var id: String { rawValue }
    var title: String {
        switch self {
        case .monochrome: "Monochrome"
        case .colorAutomatic: "Colour, follows light or dark"
        case .colorLight: "Colour, light menu bar"
        case .colorDark: "Colour, dark menu bar"
        }
    }
}

enum ArrangeTarget: String, CaseIterable, Identifiable, Sendable {
    case displayUnderMouse
    case displayWithFocusedWindow

    var id: String { rawValue }
    var title: String {
        switch self {
        case .displayUnderMouse: "Display under the pointer"
        case .displayWithFocusedWindow: "Display with the active window"
        }
    }
}

/// All user settings. Observable, so the Settings window and the app react to
/// changes immediately; every change is written to UserDefaults right away.
@MainActor
@Observable
final class Settings {
    @ObservationIgnored private let defaults: UserDefaults
    /// Called after any change that affects arranging (gaps, margins, ratios...).
    @ObservationIgnored var onLayoutChange: (() -> Void)?

    // MARK: Layout

    var gap: Double {
        didSet {
            save(gap, "gap")
            onLayoutChange?()
        }
    }
    var outerMargin: Double {
        didSet {
            save(outerMargin, "outerMargin")
            onLayoutChange?()
        }
    }
    var masterRatio: Double {
        didSet {
            save(masterRatio, "masterRatio")
            onLayoutChange?()
        }
    }
    var maxWindows: Int {
        didSet {
            save(maxWindows, "maxWindows")
            onLayoutChange?()
        }
    }
    /// Pressing Arrange again within 2 s switches to the next layout.
    var cycleOnRepeat: Bool {
        didSet {
            save(cycleOnRepeat, "cycleOnRepeat")
            onLayoutChange?()
        }
    }
    var arrangeTarget: ArrangeTarget { didSet { save(arrangeTarget.rawValue, "arrangeTarget") } }
    var menuBarIconStyle: MenuBarIconStyle { didSet { save(menuBarIconStyle.rawValue, "menuBarIconStyle") } }

    // MARK: Feedback and appearance

    var showArrangeHUD: Bool { didSet { save(showArrangeHUD, "showArrangeHUD") } }
    var showActionHUD: Bool { didSet { save(showActionHUD, "showActionHUD") } }
    /// Put windows back in the last layout of each display after a monitor is connected or disconnected.
    var rearrangeOnDisplayChange: Bool { didSet { save(rearrangeOnDisplayChange, "rearrangeOnDisplayChange") } }
    /// Drag a window to a screen edge or corner to snap it.
    var snapOnDrag: Bool { didSet { save(snapOnDrag, "snapOnDrag") } }
    var showMenuBarIcon: Bool { didSet { save(showMenuBarIcon, "showMenuBarIcon") } }

    // MARK: Apps

    /// Apps whose window is always the primary one when present, in priority order.
    var primaryApps: [String] { didSet { save(primaryApps, "primaryApps") } }
    /// Apps ordino never moves.
    var ignoredApps: [String] { didSet { save(ignoredApps, "excludedBundleIDs") } }
    /// Per-app placement rules: bundle ID -> WindowAction raw value. Ruled apps are left out of
    /// layouts and put in their place after each arrange.
    var appRules: [String: String] { didSet { save(appRules, "appRules") } }
    /// User-defined grid layouts (Settings › Layouts › Custom layouts), stored as JSON.
    var customLayouts: [CustomLayout] {
        didSet { if let data = try? JSONEncoder().encode(customLayouts) { save(data, "customLayouts") } }
    }
    /// Saved workspaces (Settings › Layouts › Workspaces), stored as JSON.
    var workspaces: [Workspace] {
        didSet { if let data = try? JSONEncoder().encode(workspaces) { save(data, "workspaces") } }
    }

    // MARK: Updates and shortcuts

    var betaUpdates: Bool { didSet { save(betaUpdates, "betaUpdates") } }
    var shortcutPreset: ShortcutPreset { didSet { save(shortcutPreset.rawValue, "shortcutPreset") } }

    /// Remembered layout per (display, window count). Written by the coordinator.
    var preferredLayouts: [String: LayoutID] {
        didSet { save(preferredLayouts.mapValues(\.rawValue), "preferredLayouts") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        gap = defaults.object(forKey: "gap") as? Double ?? 8
        outerMargin =
            defaults.object(forKey: "outerMargin") as? Double ?? (defaults.object(forKey: "gap") as? Double ?? 8)
        masterRatio = defaults.object(forKey: "masterRatio") as? Double ?? 0.55
        maxWindows = defaults.object(forKey: "maxWindows") as? Int ?? 9
        cycleOnRepeat = defaults.object(forKey: "cycleOnRepeat") as? Bool ?? true
        arrangeTarget =
            defaults.string(forKey: "arrangeTarget").flatMap(ArrangeTarget.init(rawValue:)) ?? .displayUnderMouse
        menuBarIconStyle =
            defaults.string(forKey: "menuBarIconStyle").flatMap(MenuBarIconStyle.init(rawValue:)) ?? .monochrome
        showArrangeHUD = defaults.object(forKey: "showArrangeHUD") as? Bool ?? true
        showActionHUD = defaults.object(forKey: "showActionHUD") as? Bool ?? false
        rearrangeOnDisplayChange = defaults.object(forKey: "rearrangeOnDisplayChange") as? Bool ?? true
        snapOnDrag = defaults.object(forKey: "snapOnDrag") as? Bool ?? true
        appRules = defaults.dictionary(forKey: "appRules") as? [String: String] ?? [:]
        customLayouts =
            (defaults.data(forKey: "customLayouts")).flatMap {
                try? JSONDecoder().decode([CustomLayout].self, from: $0)
            }
            ?? []
        workspaces =
            (defaults.data(forKey: "workspaces")).flatMap { try? JSONDecoder().decode([Workspace].self, from: $0) }
            ?? []
        showMenuBarIcon = defaults.object(forKey: "showMenuBarIcon") as? Bool ?? true
        primaryApps = defaults.stringArray(forKey: "primaryApps") ?? []
        ignoredApps = defaults.stringArray(forKey: "excludedBundleIDs") ?? []
        betaUpdates = defaults.bool(forKey: "betaUpdates")
        // ⌃⌥ arrows by default: ⌥⌘ arrows (Spectacle) would take over tab switching in browsers.
        shortcutPreset = defaults.string(forKey: "shortcutPreset").flatMap(ShortcutPreset.init(rawValue:)) ?? .rectangle
        let raw = defaults.dictionary(forKey: "preferredLayouts") as? [String: String] ?? [:]
        preferredLayouts = raw.compactMapValues(LayoutID.init(rawValue:))
    }

    /// Settings from 0.1.0-beta.2 or earlier exist (this is an update, not a new install).
    var isUpgradeFromEarlierVersion: Bool {
        ["gap", "preferredLayouts", "primaryApps", "excludedBundleIDs", "betaUpdates", "SULastCheckTime"]
            .contains { defaults.object(forKey: $0) != nil }
    }

    /// True until shortcuts have been set up once (first launch).
    var needsShortcutSetup: Bool {
        get { !defaults.bool(forKey: "shortcutsInitialized") }
        set { defaults.set(!newValue, forKey: "shortcutsInitialized") }
    }

    var preferences: LayoutPreferences {
        var p = LayoutPreferences()
        p.gap = gap
        p.outerPadding = .init(all: outerMargin)
        p.masterRatio = masterRatio
        p.maxWindows = maxWindows
        return p
    }

    var windowActionEngine: WindowActionEngine {
        WindowActionEngine(gap: gap, outerPadding: .init(all: outerMargin))
    }

    /// Last error from changing "launch at login", shown in Settings.
    var launchAtLoginError: String?

    /// macOS wants the user to approve ordino in System Settings › Login Items.
    var launchAtLoginNeedsApproval: Bool {
        access(keyPath: \.launchAtLoginChangeCount)
        return SMAppService.mainApp.status == .requiresApproval
    }

    /// Launch at login through SMAppService. Only works from an .app bundle.
    var launchAtLogin: Bool {
        get {
            access(keyPath: \.launchAtLoginChangeCount)
            return SMAppService.mainApp.status == .enabled
        }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                launchAtLoginError = nil
            } catch {
                launchAtLoginError = error.localizedDescription
            }
            launchAtLoginChangeCount += 1
        }
    }
    private var launchAtLoginChangeCount = 0

    func resetLayoutDefaults() {
        gap = 8
        outerMargin = 8
        masterRatio = 0.55
        maxWindows = 9
        cycleOnRepeat = true
    }

    private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }
}
