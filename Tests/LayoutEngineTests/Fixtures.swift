import Geometry

@testable import LayoutEngine

enum Fixture {
    /// MacBook Pro 14" visible frame (below a 33 pt menu bar).
    static let laptop = Rect(x: 0, y: 33, w: 1512, h: 949)
    /// 27" 2560x1440 external, to the right of the laptop.
    static let external = Rect(x: 1512, y: 0, w: 2560, h: 1415)
    /// 34" ultrawide 3440x1440.
    static let ultrawide = Rect(x: 0, y: 25, w: 3440, h: 1415)
    /// 1440x2560 portrait display.
    static let portrait = Rect(x: 0, y: 25, w: 1440, h: 2535)

    static let displays: [(String, Rect)] = [
        ("laptop", laptop), ("external", external), ("ultrawide", ultrawide), ("portrait", portrait),
    ]

    /// `n` overlapping windows scattered around the area; window 1 is focused.
    static func windows(_ n: Int, in area: Rect, focused: WindowID? = 1) -> [WindowInfo] {
        (0..<n).map { i in
            let id = WindowID(i + 1)
            let f = Rect(
                x: area.x + 40 + Double(i * 53 % 400),
                y: area.y + 30 + Double(i * 37 % 300),
                w: 900, h: 640)
            return WindowInfo(id: id, frame: f, isFocused: id == focused)
        }
    }
}

extension LayoutPlan {
    var sortedFrames: [Rect] { frames.keys.sorted().map { frames[$0]! } }
}
