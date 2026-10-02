import Carbon.HIToolbox

/// A system-wide keyboard shortcut. Carbon hot keys work without the Accessibility permission.
final class HotKey {
    private static var nextID: UInt32 = 1

    private let id: UInt32
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let onPress: () -> Void
    private let onRelease: (() -> Void)?

    /// Returns nil if the system refuses the shortcut, for example because another app registered it.
    /// `onRelease` runs when the user lets go of the key.
    init?(_ shortcut: Shortcut, onPress: @escaping () -> Void, onRelease: (() -> Void)? = nil) {
        self.onPress = onPress
        self.onRelease = onRelease
        id = Self.nextID
        Self.nextID += 1

        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                // Each hot key has its own handler, and every handler sees every press and release:
                // pass the events of other hot keys on.
                var pressed = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
                let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
                guard status == noErr, pressed.id == hotKey.id else { return OSStatus(eventNotHandledErr) }
                if GetEventKind(event) == UInt32(kEventHotKeyReleased) {
                    hotKey.onRelease?()
                } else {
                    hotKey.onPress()
                }
                return noErr
            },
            eventTypes.count, &eventTypes, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        guard installStatus == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: OSType(0x5041_5452), id: id)  // "PATR"
        let registerStatus = RegisterEventHotKey(
            UInt32(shortcut.keyCode), UInt32(shortcut.modifiers), hotKeyID, GetApplicationEventTarget(), 0,
            &hotKeyRef)
        guard registerStatus == noErr else {
            // The handler holds an unretained pointer to this object, so it must not outlive it.
            if let handlerRef { RemoveEventHandler(handlerRef) }
            handlerRef = nil
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
