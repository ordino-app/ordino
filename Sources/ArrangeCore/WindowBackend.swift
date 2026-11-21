import Geometry
import LayoutEngine

/// A display as the coordinator sees it.
public struct DisplaySnapshot: Sendable, Hashable {
    /// Stable identifier (display UUID).
    public let id: String
    public let name: String
    /// Usable area in Quartz global coordinates.
    public let visibleFrame: Rect

    public init(id: String, name: String, visibleFrame: Rect) {
        self.id = id
        self.name = name
        self.visibleFrame = visibleFrame
    }
}

/// Eligible windows on one display at one moment.
public struct WindowSnapshot: Sendable {
    /// Front to back.
    public var windows: [WindowInfo]
    /// Human-readable app name per window, for previews and messages.
    public var appNames: [WindowID: String]
    /// Windows that were seen but not eligible (minimized, panels, full screen...).
    public var skippedCount: Int

    public init(windows: [WindowInfo], appNames: [WindowID: String] = [:], skippedCount: Int = 0) {
        self.windows = windows
        self.appNames = appNames
        self.skippedCount = skippedCount
    }
}

/// Everything the coordinator needs from the outside world. The real
/// implementation talks to the Accessibility API; tests use a fake.
@MainActor
public protocol WindowBackend: AnyObject {
    /// The display to arrange (by default the one under the mouse).
    func targetDisplay() -> DisplaySnapshot?
    /// Eligible windows on `display`. `focusedID` marks the window that becomes master.
    func snapshot(of display: DisplaySnapshot, focusedID: WindowID?) -> WindowSnapshot
    /// Moves windows and returns the frames they actually ended up with
    /// (`nil` when a frame could not be read back).
    func apply(_ frames: [WindowID: Rect]) async -> [WindowID: Rect?]
}
