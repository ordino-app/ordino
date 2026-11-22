import AppKit
import Geometry
import KeyboardShortcuts
import LayoutEngine
import WindowKit

/// A user-defined grid layout, e.g. "3 Columns" for an ultrawide display.
struct CustomLayout: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var columns: Int
    var rows: Int

    var shortcutName: KeyboardShortcuts.Name { .init("customLayout-\(id.uuidString)") }
    var cells: Int { columns * rows }
}

/// Puts the most recently used windows of a display into a custom grid; windows beyond the grid's cells
/// stay where they are.
@MainActor
final class CustomLayoutController {
    private let settings: Settings
    private var registered: Set<UUID> = []
    private let mover = WindowMover()

    init(settings: Settings) {
        self.settings = settings
    }

    func apply(_ layout: CustomLayout, on display: DisplayInfo) async -> Int {
        let windows = WindowDiscovery().windows(on: display, focusedID: nil).windows
            .filter { w in !(w.bundleID.map(settings.ignoredApps.contains) ?? false) }
            .sorted { $0.zIndex < $1.zIndex }
        let m = settings.outerMargin
        let area = Rect(
            x: display.visibleFrame.x + m, y: display.visibleFrame.y + m,
            w: display.visibleFrame.w - 2 * m, h: display.visibleFrame.h - 2 * m)
        let cells = GridLayout.frames(in: area, columns: layout.columns, rows: layout.rows, gap: settings.gap)
        let pairs = Array(zip(windows, cells))
        guard !pairs.isEmpty else { return 0 }
        _ = await mover.apply(
            Dictionary(pairs.map { ($0.0.info.id, $0.1) }, uniquingKeysWith: { a, _ in a }), to: pairs.map(\.0))
        return pairs.count
    }

    func registerShortcuts(perform: @escaping @MainActor (UUID) -> Void) {
        for layout in settings.customLayouts where !registered.contains(layout.id) {
            registered.insert(layout.id)
            let id = layout.id
            KeyboardShortcuts.onKeyDown(for: layout.shortcutName) { perform(id) }
        }
    }

    func add() {
        settings.customLayouts.append(CustomLayout(name: "3 Columns", columns: 3, rows: 1))
    }

    func delete(_ id: UUID) {
        if let l = settings.customLayouts.first(where: { $0.id == id }) { KeyboardShortcuts.reset(l.shortcutName) }
        settings.customLayouts.removeAll { $0.id == id }
    }
}
