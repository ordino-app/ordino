import Foundation
import LayoutEngine
import ServiceManagement

/// Persistent user settings (UserDefaults).
@MainActor
final class Settings {
    private let defaults = UserDefaults.standard

    var gap: Double {
        get { defaults.object(forKey: "gap") as? Double ?? 8 }
        set { defaults.set(newValue, forKey: "gap") }
    }

    var preferredLayouts: [String: LayoutID] {
        get {
            let raw = defaults.dictionary(forKey: "preferredLayouts") as? [String: String] ?? [:]
            return raw.compactMapValues(LayoutID.init(rawValue:))
        }
        set { defaults.set(newValue.mapValues(\.rawValue), forKey: "preferredLayouts") }
    }

    var excludedBundleIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: "excludedBundleIDs") ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: "excludedBundleIDs") }
    }

    var preferences: LayoutPreferences {
        var p = LayoutPreferences()
        p.gap = gap
        p.outerPadding = .init(all: gap)
        return p
    }

    /// Launch at login through SMAppService. Only works from an .app bundle.
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("ordino: launch at login change failed: \(error.localizedDescription)")
            }
        }
    }
}
