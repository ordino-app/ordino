import Carbon.HIToolbox

/// Global hotkeys through Carbon's RegisterEventHotKey. Needs no extra
/// permission (unlike event taps, which need Input Monitoring).
@MainActor
final class HotKeys {
    static let shared = HotKeys()

    struct Combo: Hashable {
        let keyCode: UInt32
        let modifiers: UInt32

        /// ⌃⌥⌘ + key
        static func hyper(_ keyCode: Int) -> Combo {
            Combo(keyCode: UInt32(keyCode), modifiers: UInt32(controlKey | optionKey | cmdKey))
        }
    }

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []
    private var nextID: UInt32 = 1
    private var installed = false
    private static let signature: OSType = 0x4F52_444E  // "ORDN"

    /// Returns false when the combination is taken by another app.
    @discardableResult
    func register(_ combo: Combo, _ handler: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combo.keyCode, combo.modifiers, EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        refs.append(ref)
        handlers[id] = handler
        return true
    }

    func unregisterAll() {
        for ref in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
        handlers.removeAll()
    }

    fileprivate func fire(_ id: UInt32) { handlers[id]?() }

    private func installHandlerIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                var hotKey = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &hotKey)
                guard status == noErr, hotKey.signature == HotKeys.signature else {
                    return OSStatus(eventNotHandledErr)
                }
                let id = hotKey.id
                // Carbon delivers application events on the main thread.
                MainActor.assumeIsolated { HotKeys.shared.fire(id) }
                return noErr
            }, 1, &spec, nil, nil)
    }
}
