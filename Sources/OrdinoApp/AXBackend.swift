import ArrangeCore
import Geometry
import LayoutEngine
import WindowKit

/// Connects the coordinator to the real Accessibility layer.
@MainActor
final class AXBackend: WindowBackend {
    private var discovery = WindowDiscovery()
    private let mover = WindowMover()
    /// Windows from the latest snapshot, needed to move them.
    private var current: [WindowID: DiscoveredWindow] = [:]
    /// When set, snapshots keep only this many windows, the most recently used first ("Arrange Two Recent").
    var windowLimit: Int?

    var excludedBundleIDs: Set<String> {
        get { discovery.excludedBundleIDs }
        set { discovery.excludedBundleIDs = newValue }
    }

    func targetDisplay() -> DisplaySnapshot? {
        Displays.underMouse().map {
            DisplaySnapshot(id: $0.uuid, name: $0.name, visibleFrame: $0.visibleFrame)
        }
    }

    func snapshot(of display: DisplaySnapshot, focusedID: WindowID?) -> WindowSnapshot {
        guard let info = Displays.all().first(where: { $0.uuid == display.id }) else {
            return WindowSnapshot(windows: [])
        }
        let result = discovery.windows(on: info, focusedID: focusedID)
        let found =
            windowLimit.map { Array(result.windows.sorted { $0.zIndex < $1.zIndex }.prefix($0)) } ?? result.windows
        // Only the latest snapshot is kept, so closed windows' AX handles are released.
        current = Dictionary(found.map { ($0.info.id, $0) }, uniquingKeysWith: { a, _ in a })
        return WindowSnapshot(
            windows: found.map(\.info),
            appNames: Dictionary(found.map { ($0.info.id, $0.appName) }, uniquingKeysWith: { a, _ in a }),
            bundleIDs: Dictionary(
                found.compactMap { w in w.bundleID.map { (w.info.id, $0) } }, uniquingKeysWith: { a, _ in a }),
            titles: Dictionary(found.map { ($0.info.id, $0.title) }, uniquingKeysWith: { a, _ in a }),
            skippedCount: result.skipped.count)
    }

    func apply(_ frames: [WindowID: Rect]) async -> [WindowID: Rect?] {
        let windows = frames.keys.compactMap { current[$0] }
        let outcomes = await mover.apply(frames, to: windows)
        var result: [WindowID: Rect?] = [:]
        for id in frames.keys { result[id] = .some(nil) }
        for o in outcomes { result[o.id] = o.actual }
        return result
    }
}
