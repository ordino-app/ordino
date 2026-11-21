import AppKit
import CoreGraphics
import Geometry

/// One connected display, with frames in Quartz global coordinates.
public struct DisplayInfo: Sendable, Hashable, CustomStringConvertible {
    public let id: CGDirectDisplayID
    /// Stable across reconnects (unlike the NSScreen index).
    public let uuid: String
    public let name: String
    public let frame: Rect
    /// Frame minus menu bar, notch and Dock.
    public let visibleFrame: Rect

    public var description: String { "\(name) [\(id)] frame \(frame) visible \(visibleFrame)" }
}

@MainActor
public enum Displays {
    /// Height of the primary display: the screen whose AppKit origin is (0, 0).
    static var primaryHeight: Double {
        let primary = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first
        return Double(primary?.frame.height ?? 0)
    }

    public static func all() -> [DisplayInfo] {
        let ph = primaryHeight
        return NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            let id = CGDirectDisplayID(number.uint32Value)
            var uuid = "\(id)"
            if let cf = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
                let s = CFUUIDCreateString(nil, cf) as String?
            {
                uuid = s
            }
            return DisplayInfo(
                id: id, uuid: uuid, name: screen.localizedName,
                frame: Rect(screen.frame).flippedVertically(primaryHeight: ph),
                visibleFrame: Rect(screen.visibleFrame).flippedVertically(primaryHeight: ph))
        }
    }

    /// The display under the mouse pointer (the default arrange target).
    public static func underMouse() -> DisplayInfo? {
        let ph = primaryHeight
        let m = NSEvent.mouseLocation  // AppKit coordinates
        let qx = Double(m.x)
        let qy = ph - Double(m.y)
        let displays = all()
        return displays.first { $0.frame.contains(pointX: qx, y: qy) } ?? displays.first
    }
}

extension Rect {
    init(_ r: CGRect) {
        self.init(x: Double(r.origin.x), y: Double(r.origin.y), w: Double(r.width), h: Double(r.height))
    }

    var cgRect: CGRect { CGRect(x: x, y: y, width: w, height: h) }
}
