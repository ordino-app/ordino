import AppKit
import ImageIO

/// Small, cached images for the menu's screen preview: each display's desktop
/// picture (downscaled once) and app icons.
@MainActor
enum MenuVisuals {
    private static var wallpapers: [String: NSImage] = [:]
    private static var icons: [String: NSImage] = [:]

    /// The desktop picture of the display with this UUID, about 640 px wide.
    static func wallpaper(forDisplayUUID uuid: String) -> NSImage? {
        guard let screen = screen(forUUID: uuid),
            let url = NSWorkspace.shared.desktopImageURL(for: screen)
        else { return nil }
        let key = url.path
        if let cached = wallpapers[key] { return cached }
        guard let image = thumbnail(of: url, maxPixels: 640) else { return nil }
        wallpapers[key] = image
        return image
    }

    static func icon(forBundleID bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = icons[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons[bundleID] = icon
        return icon
    }

    private static func screen(forUUID uuid: String) -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                let cf = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(number.uint32Value))?.takeRetainedValue()
            else { return false }
            return (CFUUIDCreateString(nil, cf) as String?) == uuid
        }
    }

    /// Decodes only a small version of a (possibly huge, possibly HEIC) picture.
    private static func thumbnail(of url: URL, maxPixels: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
