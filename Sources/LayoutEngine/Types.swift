import Geometry

/// Identifier of a window. Backed by `CGWindowID` in the real backend.
public typealias WindowID = UInt32

/// What the engine needs to know about one window. Pure data.
public struct WindowInfo: Sendable, Hashable, Identifiable {
    public let id: WindowID
    /// Current frame in Quartz global coordinates.
    public var frame: Rect
    /// Smallest size the window accepts, if known (learned or reported).
    public var minSize: Size?
    /// False for fixed-size windows (size attribute not settable).
    public var isResizable: Bool
    /// True for the window the user was working in when arrange was triggered.
    public var isFocused: Bool

    public init(
        id: WindowID, frame: Rect, minSize: Size? = nil,
        isResizable: Bool = true, isFocused: Bool = false
    ) {
        self.id = id
        self.frame = frame
        self.minSize = minSize
        self.isResizable = isResizable
        self.isFocused = isFocused
    }
}

/// The built-in layouts.
public enum LayoutID: String, Sendable, Hashable, Codable, CaseIterable, CustomStringConvertible {
    /// One window filling the area.
    case maximize
    /// One window centered at a fraction of the width (for wide displays).
    case centered
    /// Equal columns.
    case columns
    /// Equal rows.
    case rows
    /// One large master plus the rest stacked beside it.
    case masterStack
    /// Rows x columns grid, chosen by a cost function.
    case grid
    /// Binary space partition (spiral-free, alternating split axis).
    case bsp

    public var description: String {
        switch self {
        case .maximize: "Maximize"
        case .centered: "Centered"
        case .columns: "Columns"
        case .rows: "Rows"
        case .masterStack: "Master + Stack"
        case .grid: "Grid"
        case .bsp: "BSP"
        }
    }

    /// Whether this layout can place `count` windows.
    public func supports(count: Int) -> Bool {
        switch self {
        case .maximize, .centered: count == 1
        case .bsp: (1...6).contains(count)
        case .columns, .rows, .masterStack, .grid: count >= 1
        }
    }
}

/// Coarse classification of the target area used by the chooser.
public enum DisplayShape: Sendable, Hashable {
    case landscape
    case ultrawide
    case portrait
}

/// User-tunable knobs. Defaults are the product defaults.
public struct LayoutPreferences: Sendable, Hashable, Codable {
    /// Gap between neighbouring windows, in points.
    public var gap: Double = 8
    /// Padding between the windows and the edge of the usable area.
    public var outerPadding: Insets = Insets(all: 8)
    /// Share of the long axis given to the master window (clamped to 0.3...0.8).
    public var masterRatio: Double = 0.55
    /// When true and the layout has a master slot, the focused window gets it.
    public var focusedIsMaster: Bool = true
    /// Windows beyond this count (in z-order) are left untouched.
    public var maxWindows: Int = 9
    /// Width fraction for the `.centered` layout.
    public var centeredWidthFraction: Double = 0.65
    /// Aspect ratio above which a display counts as ultrawide.
    public var ultrawideAspect: Double = 2.0
    /// Aspect ratio below which a display counts as portrait.
    public var portraitAspect: Double = 1.0
    /// Preferred aspect ratio of a grid cell.
    public var targetCellAspect: Double = 1.5
    /// Grid cells narrower / shorter than this are penalised.
    public var minComfortableCell: Size = Size(w: 480, h: 320)
    /// Ultrawide: use one column per window when each column is at least this wide.
    public var ultrawideColumnMinWidth: Double = 800

    public init() {}

    public var clampedMasterRatio: Double { min(0.8, max(0.3, masterRatio)) }
}

/// Input to the engine.
public struct LayoutContext: Sendable {
    /// Usable area of the display (visible frame, Quartz coordinates). Outer
    /// padding from the preferences is applied by the engine.
    public var area: Rect
    /// Eligible windows in z-order, frontmost first.
    public var windows: [WindowInfo]
    public var preferences: LayoutPreferences

    public init(area: Rect, windows: [WindowInfo], preferences: LayoutPreferences = .init()) {
        self.area = area
        self.windows = windows
        self.preferences = preferences
    }
}

/// Output of the engine.
public struct LayoutPlan: Sendable, Hashable {
    /// The layout that was used.
    public let layout: LayoutID
    /// Ordered list of layouts available for this window count (for cycling).
    public let candidates: [LayoutID]
    /// Target frame for every placed window.
    public let frames: [WindowID: Rect]
    /// Windows that were not placed (beyond `maxWindows`), frontmost first.
    public let unplaced: [WindowID]
    /// False when minimum sizes could not all be honoured.
    public let isFeasible: Bool

    /// The layout after `layout` in `candidates`, wrapping around.
    public var nextLayout: LayoutID {
        guard !candidates.isEmpty else { return layout }
        guard let i = candidates.firstIndex(of: layout) else { return candidates[0] }
        return candidates[(i + 1) % candidates.count]
    }

    /// The layout before `layout` in `candidates`, wrapping around.
    public var previousLayout: LayoutID {
        guard !candidates.isEmpty else { return layout }
        guard let i = candidates.firstIndex(of: layout) else { return candidates[candidates.count - 1] }
        return candidates[(i - 1 + candidates.count) % candidates.count]
    }
}
