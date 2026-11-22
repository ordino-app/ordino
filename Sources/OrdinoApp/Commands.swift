import AppKit
import KeyboardShortcuts
import LayoutEngine

/// Everything ordino can do from a shortcut or a menu item.
enum Command: Hashable, Identifiable, Sendable {
    case arrange
    case nextLayout
    case previousLayout
    case rotate
    case undo
    /// Arrange only the N most recently used windows of the display; the rest stay put.
    case arrangeRecent(Int)
    case window(WindowAction)

    static let arrangeCommands: [Command] = [
        .arrange, .arrangeRecent(2), .arrangeRecent(3), .nextLayout, .previousLayout, .rotate, .undo,
    ]
    static let all: [Command] = arrangeCommands + WindowAction.allCases.map { .window($0) }

    var id: String { shortcutName.rawValue }

    var title: String {
        switch self {
        case .arrange: "Arrange Windows"
        case .nextLayout: "Next Layout"
        case .previousLayout: "Previous Layout"
        case .rotate: "Rotate Windows"
        case .undo: "Undo Arrange"
        case .arrangeRecent(let n): "Arrange \(n == 2 ? "Two" : n == 3 ? "Three" : "\(n)") Recent Windows"
        case .window(let action): action.title
        }
    }

    /// Storage key for the user's shortcut. Names can't contain dots.
    var shortcutName: KeyboardShortcuts.Name {
        switch self {
        case .arrange: .init("arrange")
        case .nextLayout: .init("nextLayout")
        case .previousLayout: .init("previousLayout")
        case .rotate: .init("rotate")
        case .undo: .init("undoArrange")
        case .arrangeRecent(let n): .init("arrangeRecent\(n)")
        case .window(let action): .init("window-\(action.rawValue)")
        }
    }
}

/// Ready-made shortcut sets for the window actions. ordino's own commands
/// (arrange, cycle, rotate, undo) are the same in every preset.
enum ShortcutPreset: String, CaseIterable, Identifiable, Sendable {
    /// The classic Spectacle keys: ⌥⌘ arrows for halves, ⌃⌘ for corners.
    case spectacle
    /// Rectangle's own defaults: ⌃⌥ arrows, U/I/J/K corners, D/F/G thirds.
    case rectangle
    /// Only ordino's arrange shortcuts; window actions from the menu.
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spectacle: "Spectacle style (⌥⌘ arrows)"
        case .rectangle: "Rectangle style (⌃⌥ arrows)"
        case .none: "No window shortcuts"
        }
    }

    typealias S = KeyboardShortcuts.Shortcut

    static let arrangeDefaults: [Command: S] = [
        .arrange: S(.a, modifiers: [.control, .option, .command]),
        .nextLayout: S(.rightBracket, modifiers: [.control, .option, .command]),
        .previousLayout: S(.leftBracket, modifiers: [.control, .option, .command]),
        .rotate: S(.r, modifiers: [.control, .option, .command]),
        .undo: S(.z, modifiers: [.control, .option, .command]),
    ]

    var windowShortcuts: [WindowAction: S] {
        let optCmd: NSEvent.ModifierFlags = [.option, .command]
        let ctrlCmd: NSEvent.ModifierFlags = [.control, .command]
        let ctrlShiftCmd: NSEvent.ModifierFlags = [.control, .shift, .command]
        let ctrlOpt: NSEvent.ModifierFlags = [.control, .option]
        let ctrlOptShift: NSEvent.ModifierFlags = [.control, .option, .shift]
        let ctrlOptCmd: NSEvent.ModifierFlags = [.control, .option, .command]
        switch self {
        case .spectacle:
            return [
                .leftHalf: S(.leftArrow, modifiers: optCmd), .rightHalf: S(.rightArrow, modifiers: optCmd),
                .topHalf: S(.upArrow, modifiers: optCmd), .bottomHalf: S(.downArrow, modifiers: optCmd),
                .topLeft: S(.leftArrow, modifiers: ctrlCmd), .topRight: S(.rightArrow, modifiers: ctrlCmd),
                .bottomLeft: S(.leftArrow, modifiers: ctrlShiftCmd),
                .bottomRight: S(.rightArrow, modifiers: ctrlShiftCmd),
                .maximize: S(.f, modifiers: optCmd), .maximizeHeight: S(.upArrow, modifiers: ctrlOptShift),
                .larger: S(.rightArrow, modifiers: ctrlOptShift), .smaller: S(.leftArrow, modifiers: ctrlOptShift),
                .center: S(.c, modifiers: optCmd), .restore: S(.delete, modifiers: ctrlOpt),
                .nextDisplay: S(.rightArrow, modifiers: ctrlOptCmd),
                .previousDisplay: S(.leftArrow, modifiers: ctrlOptCmd),
            ]
        case .rectangle:
            return [
                .leftHalf: S(.leftArrow, modifiers: ctrlOpt), .rightHalf: S(.rightArrow, modifiers: ctrlOpt),
                .topHalf: S(.upArrow, modifiers: ctrlOpt), .bottomHalf: S(.downArrow, modifiers: ctrlOpt),
                .topLeft: S(.u, modifiers: ctrlOpt), .topRight: S(.i, modifiers: ctrlOpt),
                .bottomLeft: S(.j, modifiers: ctrlOpt), .bottomRight: S(.k, modifiers: ctrlOpt),
                .firstThird: S(.d, modifiers: ctrlOpt), .centerThird: S(.f, modifiers: ctrlOpt),
                .lastThird: S(.g, modifiers: ctrlOpt), .firstTwoThirds: S(.e, modifiers: ctrlOpt),
                .lastTwoThirds: S(.t, modifiers: ctrlOpt),
                .maximize: S(.return, modifiers: ctrlOpt), .maximizeHeight: S(.upArrow, modifiers: ctrlOptShift),
                .larger: S(.equal, modifiers: ctrlOpt), .smaller: S(.minus, modifiers: ctrlOpt),
                .center: S(.c, modifiers: ctrlOpt), .restore: S(.delete, modifiers: ctrlOpt),
                .nextDisplay: S(.rightArrow, modifiers: ctrlOptCmd),
                .previousDisplay: S(.leftArrow, modifiers: ctrlOptCmd),
            ]
        case .none:
            return [:]
        }
    }

    /// Replaces every window-action shortcut with this preset's; keeps the arrange shortcuts.
    @MainActor
    func apply() {
        let map = windowShortcuts
        for action in WindowAction.allCases {
            KeyboardShortcuts.setShortcut(map[action], for: Command.window(action).shortcutName)
        }
    }

    @MainActor
    static func applyArrangeDefaults() {
        for command in Command.arrangeCommands {
            KeyboardShortcuts.setShortcut(arrangeDefaults[command], for: command.shortcutName)
        }
    }

    /// Next/previous layout as they were in 0.1.0-beta.2, kept for upgraders.
    static let legacyLayoutCycling: [Command: S] = [
        .nextLayout: S(.rightArrow, modifiers: [.control, .option, .command]),
        .previousLayout: S(.leftArrow, modifiers: [.control, .option, .command]),
    ]

    /// Bundle IDs of window managers whose shortcuts would collide with a preset.
    static let knownWindowManagers: [String: String] = [
        "com.knollsoft.Rectangle": "Rectangle",
        "com.knollsoft.Hookshot": "Rectangle Pro",
        "com.divisiblebyzero.Spectacle": "Spectacle",
        "com.crowdcafe.windowmagnet": "Magnet",
        "com.manytricks.Moom": "Moom",
        "com.hegenberg.BetterSnapTool": "BetterSnapTool",
    ]

    /// A running window manager, if any (its shortcuts would win or collide).
    @MainActor
    static func runningWindowManager() -> String? {
        NSWorkspace.shared.runningApplications.lazy
            .compactMap { $0.bundleIdentifier.flatMap { knownWindowManagers[$0] } }
            .first
    }
}
