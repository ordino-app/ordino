import AppKit

/// Remembers the last app other than ordino that was frontmost, so "the window
/// the user was working in" survives ordino briefly becoming active.
@MainActor
public final class FrontmostAppTracker {
    public static let shared = FrontmostAppTracker()
    public private(set) var lastExternalPID: pid_t?
    private var observer: NSObjectProtocol?

    public func start() {
        guard observer == nil else { return }
        record(NSWorkspace.shared.frontmostApplication)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let pid = app?.processIdentifier
            MainActor.assumeIsolated { FrontmostAppTracker.shared.record(pid: pid) }
        }
    }

    private func record(_ app: NSRunningApplication?) { record(pid: app?.processIdentifier) }

    private func record(pid: pid_t?) {
        guard let pid, pid != ProcessInfo.processInfo.processIdentifier else { return }
        lastExternalPID = pid
    }
}
