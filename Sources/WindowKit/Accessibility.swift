import AXPrivate
import AppKit
import ApplicationServices
import Geometry

/// Accessibility (TCC) permission helpers.
public enum AccessibilityPermission {
    /// Whether this process may control other apps through the AX API.
    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that points the user to System Settings.
    /// The literal key avoids touching the non-Sendable global
    /// `kAXTrustedCheckOptionPrompt` under Swift 6 strict concurrency.
    @discardableResult
    public static func requestWithPrompt() -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Deep link to Privacy & Security > Accessibility.
    public static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
}

/// Attribute names as literals (the imported constants are awkward in Swift 6).
enum AXAttr {
    static let windows = "AXWindows"
    static let focusedWindow = "AXFocusedWindow"
    static let position = "AXPosition"
    static let size = "AXSize"
    static let subrole = "AXSubrole"
    static let role = "AXRole"
    static let minimized = "AXMinimized"
    static let fullScreen = "AXFullScreen"
    static let title = "AXTitle"
    static let enhancedUserInterface = "AXEnhancedUserInterface"
    static let standardWindow = "AXStandardWindow"
}

/// Thin, synchronous wrappers over the C AX API. AX elements are not
/// `Sendable`; everything here is meant to run on one thread (the main actor
/// in the prototype, a per-app actor later).
extension AXUIElement {
    func value(_ attribute: String) -> CFTypeRef? {
        var out: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(self, attribute as CFString, &out)
        return err == .success ? out : nil
    }

    func string(_ attribute: String) -> String? { value(attribute) as? String }
    func bool(_ attribute: String) -> Bool? { (value(attribute) as? NSNumber)?.boolValue }

    func elements(_ attribute: String) -> [AXUIElement] {
        guard let raw = value(attribute), CFGetTypeID(raw) == CFArrayGetTypeID() else { return [] }
        let array = unsafeDowncast(raw, to: CFArray.self)
        return (0..<CFArrayGetCount(array)).compactMap { i in
            guard let p = CFArrayGetValueAtIndex(array, i) else { return nil }
            let obj = Unmanaged<CFTypeRef>.fromOpaque(p).takeUnretainedValue()
            guard CFGetTypeID(obj) == AXUIElementGetTypeID() else { return nil }
            return unsafeDowncast(obj, to: AXUIElement.self)
        }
    }

    func element(_ attribute: String) -> AXUIElement? {
        guard let raw = value(attribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(raw, to: AXUIElement.self)
    }

    func point(_ attribute: String) -> CGPoint? {
        guard let raw = value(attribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(unsafeDowncast(raw, to: AXValue.self), .cgPoint, &p) ? p : nil
    }

    func size(_ attribute: String) -> CGSize? {
        guard let raw = value(attribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(unsafeDowncast(raw, to: AXValue.self), .cgSize, &s) ? s : nil
    }

    @discardableResult
    func set(_ attribute: String, _ value: CFTypeRef) -> AXError {
        AXUIElementSetAttributeValue(self, attribute as CFString, value)
    }

    @discardableResult
    func set(position p: CGPoint) -> AXError {
        var p = p
        guard let v = AXValueCreate(.cgPoint, &p) else { return .failure }
        return set(AXAttr.position, v)
    }

    @discardableResult
    func set(size s: CGSize) -> AXError {
        var s = s
        guard let v = AXValueCreate(.cgSize, &s) else { return .failure }
        return set(AXAttr.size, v)
    }

    func isSettable(_ attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(self, attribute as CFString, &settable) == .success && settable.boolValue
    }

    var windowID: CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(self, &id) == .success && id != 0 ? id : nil
    }
}
