import Carbon.HIToolbox
import Foundation

/// Registers a global hotkey using the Carbon Events API.
///
/// **Why Carbon instead of CGEventTap?** CGEvent taps require "Input Monitoring" permission,
/// while Carbon `RegisterEventHotKey` works for accessory apps with no extra permissions.
/// Carbon is legacy but appropriate for a menu bar utility that just needs a global shortcut.
///
/// **Pointer safety**: the C callback receives `self` via `Unmanaged.passUnretained`. This is safe
/// because `unregister()` removes the event handler before the pointer can dangle, and `deinit`
/// calls `unregister()` as a final guard. The `isInvalidated` flag is an extra safety net for
/// any edge-case timing between handler removal and event delivery.
final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var onPress: (() -> Void)?
    private let hotKeyID: EventHotKeyID
    fileprivate var isInvalidated = false

    init(signature: String = "SHPT", id: UInt32 = 1) {
        self.hotKeyID = EventHotKeyID(signature: fourCharCode(signature), id: id)
    }

    func register(keyCode: UInt32, modifiers: UInt32, onPress: @escaping () -> Void) {
        self.onPress = onPress
        unregister()
        isInvalidated = false

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        // Safety: passUnretained is correct here because HotKeyManager owns the event handler
        // lifetime. unregister() removes the handler (clearing userData) before the pointer can
        // dangle, and deinit calls unregister() as a final guard. The isInvalidated flag provides
        // an extra safety check in the callback for any edge-case timing between removal and delivery.
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventHandler,
            1,
            &eventType,
            userData,
            &eventHandlerRef
        )
        guard installStatus == noErr else {
            return
        }

        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if registerStatus != noErr {
            unregister()
        }
    }

    func unregister() {
        isInvalidated = true
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    deinit {
        unregister()
    }

    fileprivate func handle(event: EventRef?) -> OSStatus {
        guard let event else { return OSStatus(eventNotHandledErr) }

        var eventHotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &eventHotKeyID
        )
        guard status == noErr else {
            return status
        }

        guard eventHotKeyID.signature == hotKeyID.signature, eventHotKeyID.id == hotKeyID.id else {
            return OSStatus(eventNotHandledErr)
        }
        onPress?()
        return noErr
    }
}

/// C-compatible callback bridging Carbon events back to the HotKeyManager instance.
private let hotKeyEventHandler: EventHandlerUPP = { _, eventRef, userData in
    guard let userData else {
        return noErr
    }
    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    guard !manager.isInvalidated else {
        return OSStatus(eventNotHandledErr)
    }
    return manager.handle(event: eventRef)
}

/// Convert a 4-char string to a Carbon `OSType` (e.g. "SHPO" -> 0x5348504F).
private func fourCharCode(_ value: String) -> OSType {
    value.utf8.reduce(0) { ($0 << 8) + OSType($1) }
}
