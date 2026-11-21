import AppKit
import Sparkle

/// Sparkle 2 auto-update. Checks once a day in the background; for a menu bar
/// app the "update available" alert is replaced by a gentle reminder (a dot
/// in the menu) so it never pops up over the user's work.
@MainActor
final class Updater: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    private var controller: SPUStandardUpdaterController?
    private var canCheckObservation: NSKeyValueObservation?
    private let settings: Settings
    /// Set when a scheduled check found an update the user hasn't seen yet.
    private(set) var updateAvailable = false
    var onChange: (() -> Void)?

    /// Sparkle needs a real bundle with a feed URL and public key (not `swift run`).
    var isAvailable: Bool { controller != nil }
    var canCheck: Bool { controller?.updater.canCheckForUpdates ?? false }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    init(settings: Settings) {
        self.settings = settings
        super.init()
        let info = Bundle.main.infoDictionary ?? [:]
        guard Bundle.main.bundleURL.pathExtension == "app",
            (info["SUFeedURL"] as? String)?.isEmpty == false,
            (info["SUPublicEDKey"] as? String)?.isEmpty == false
        else {
            NSLog("ordino: updates disabled (not running from a bundle with SUFeedURL and SUPublicEDKey)")
            return
        }
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        canCheckObservation = controller?.updater.observe(\.canCheckForUpdates) { [weak self] _, _ in
            Task { @MainActor in self?.onChange?() }
        }

        // Used by scripts/test-update.sh: check and install in the background right away.
        if UserDefaults.standard.bool(forKey: "ordinoCheckForUpdatesNow") {
            controller?.updater.checkForUpdatesInBackground()
        }
    }

    func checkForUpdates() {
        updateAvailable = false
        onChange?()
        controller?.checkForUpdates(nil)
    }

    // MARK: SPUUpdaterDelegate

    /// Beta users stay on the beta channel: a prerelease build (e.g. 0.2.0-beta.1)
    /// always gets newer betas, everyone else only when they tick "Beta".
    nonisolated func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        MainActor.assumeIsolated { settings.betaUpdates || Self.isPrerelease ? ["beta"] : [] }
    }

    static var isPrerelease: Bool {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)?.contains("-") ?? false
    }

    // MARK: SPUStandardUserDriverDelegate (gentle reminders)

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        // Never pop up for a scheduled check (for an LSUIElement app Sparkle reports
        // "immediate focus" right after launch, which would interrupt a login).
        // The menu bar icon and the menu show it instead.
        false
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        guard !handleShowingUpdate else { return }
        MainActor.assumeIsolated {
            updateAvailable = true
            onChange?()
        }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated {
            updateAvailable = false
            onChange?()
        }
    }
}
