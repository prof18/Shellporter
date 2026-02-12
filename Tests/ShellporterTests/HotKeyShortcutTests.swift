import Carbon.HIToolbox.Events
import Foundation
import Testing
@testable import Shellporter

@Test
func hotKeyShortcut_formatsDefaultShortcut() {
    let display = HotKeyShortcut.displayString(
        keyCode: AppConfig.defaultHotkeyKeyCode,
        modifiers: AppConfig.defaultHotkeyModifiers
    )
    #expect(display == "⌃⌥⌘T")
}

@Test
func hotKeyShortcut_mapsDefaultKeyEquivalent() {
    #expect(HotKeyShortcut.keyEquivalent(for: AppConfig.defaultHotkeyKeyCode) == "t")
}

@Test
func hotKeyShortcut_roundTripsModifierFlags() {
    let modifiers = UInt32(controlKey | optionKey | cmdKey)
    let flags = HotKeyShortcut.modifierFlags(fromCarbonModifiers: modifiers)
    let roundTrip = HotKeyShortcut.carbonModifiers(fromEventFlags: flags)
    #expect(roundTrip == modifiers)
}

@Test
func hotKeyShortcut_formatsDefaultCopyCommandShortcut() {
    let display = HotKeyShortcut.displayString(
        keyCode: AppConfig.defaultCopyCommandHotkeyKeyCode,
        modifiers: AppConfig.defaultCopyCommandHotkeyModifiers
    )
    #expect(display == "⌃⌥⌘C")
}
