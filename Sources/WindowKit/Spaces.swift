import Foundation

/// The current Mission Control Space. macOS has no public API for it; the long-standing CoreGraphics
/// server calls are looked up at run time, so a future macOS without them just turns the feature off.
public enum Spaces {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias ActiveSpace = @convention(c) (Int32) -> UInt64

    private static let functions: (MainConnection, ActiveSpace)? = {
        let handle = UnsafeMutableRawPointer(bitPattern: -2)  // RTLD_DEFAULT
        guard let conn = dlsym(handle, "CGSMainConnectionID"), let space = dlsym(handle, "CGSGetActiveSpace")
        else { return nil }
        return (unsafeBitCast(conn, to: MainConnection.self), unsafeBitCast(space, to: ActiveSpace.self))
    }()

    /// An identifier of the active Space, or nil when it can't be read.
    public static func activeSpaceID() -> String? {
        guard let (conn, space) = functions else { return nil }
        let id = space(conn())
        return id == 0 ? nil : String(id)
    }
}
