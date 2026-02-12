import AppKit
import Carbon.HIToolbox.Events
import Foundation

enum HotKeyShortcut {
    static func keyEquivalent(for keyCode: UInt32) -> String {
        keyMap[keyCode] ?? ""
    }

    static func displayString(keyCode: UInt32, modifiers: UInt32) -> String {
        var output = ""
        if modifiers & UInt32(controlKey) != 0 {
            output += "⌃"
        }
        if modifiers & UInt32(optionKey) != 0 {
            output += "⌥"
        }
        if modifiers & UInt32(shiftKey) != 0 {
            output += "⇧"
        }
        if modifiers & UInt32(cmdKey) != 0 {
            output += "⌘"
        }
        output += keyDisplayMap[keyCode] ?? "Key\(keyCode)"
        return output
    }

    static func modifierFlags(fromCarbonModifiers modifiers: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(controlKey) != 0 {
            flags.insert(.control)
        }
        if modifiers & UInt32(optionKey) != 0 {
            flags.insert(.option)
        }
        if modifiers & UInt32(shiftKey) != 0 {
            flags.insert(.shift)
        }
        if modifiers & UInt32(cmdKey) != 0 {
            flags.insert(.command)
        }
        return flags
    }

    static func carbonModifiers(fromEventFlags flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.control) {
            modifiers |= UInt32(controlKey)
        }
        if flags.contains(.option) {
            modifiers |= UInt32(optionKey)
        }
        if flags.contains(.shift) {
            modifiers |= UInt32(shiftKey)
        }
        if flags.contains(.command) {
            modifiers |= UInt32(cmdKey)
        }
        return modifiers
    }

    static func isSupportedKeyCode(_ keyCode: UInt32) -> Bool {
        keyMap[keyCode] != nil
    }

    private static let keyMap: [UInt32: String] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
        8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
        16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p", 37: "l",
        38: "j", 39: "'", 40: "k", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "n", 46: "m", 47: ".", 50: "`",
    ]

    private static let keyDisplayMap: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
        38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "N", 46: "M", 47: ".", 50: "`",
    ]
}
