import Foundation

/// `ordino://` links, for Shortcuts.app ("Open URLs"), Raycast Quicklinks, scripts (`open "ordino://arrange"`).
///
///     ordino://arrange                 arrange the display (per the Arrange setting)
///     ordino://arrange?recent=2        only the 2 most recently used windows
///     ordino://layout/columns          a specific layout (columns, rows, grid, masterStack, bsp, maximize, centered)
///     ordino://next-layout  ordino://previous-layout  ordino://rotate  ordino://undo
///     ordino://window/leftHalf         a window action on the focused window (any WindowAction name)
///     ordino://workspace/Coding        a saved workspace, by name (case-insensitive)
///     ordino://custom/3%20Columns      a custom layout, by name (case-insensitive)
public enum AutomationURL: Equatable, Sendable {
    case arrange(recent: Int?)
    case layout(LayoutID)
    case nextLayout, previousLayout, rotate, undo
    case window(WindowAction)
    case workspace(String)
    case custom(String)

    public static let scheme = "ordino"

    public init?(_ url: URL) {
        guard url.scheme?.lowercased() == Self.scheme, let host = url.host()?.lowercased() else { return nil }
        let argument = url.pathComponents.dropFirst().first?.removingPercentEncoding
        switch host {
        case "arrange":
            let recent = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "recent" }?.value.flatMap(Int.init)
            self = .arrange(recent: recent.map { max(1, $0) })
        case "layout":
            guard let raw = argument,
                let layout = LayoutID.allCases.first(where: { $0.rawValue.lowercased() == raw.lowercased() })
            else { return nil }
            self = .layout(layout)
        case "next-layout": self = .nextLayout
        case "previous-layout": self = .previousLayout
        case "rotate": self = .rotate
        case "undo": self = .undo
        case "window":
            guard let raw = argument,
                let action = WindowAction.allCases.first(where: { $0.rawValue.lowercased() == raw.lowercased() })
            else { return nil }
            self = .window(action)
        case "workspace":
            guard let name = argument, !name.isEmpty else { return nil }
            self = .workspace(name)
        case "custom":
            guard let name = argument, !name.isEmpty else { return nil }
            self = .custom(name)
        default:
            return nil
        }
    }
}
