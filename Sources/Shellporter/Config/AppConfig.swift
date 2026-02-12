import Carbon.HIToolbox.Events
import Foundation

/// Supported terminal applications. Each case knows its bundle ID (for detection/focusing),
/// display name, and a default command template for the "Custom" fallback.
enum TerminalChoice: String, Codable, CaseIterable, Identifiable {
    case ghostty
    case kitty
    case terminal
    case iTerm2
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ghostty:
            return "Ghostty"
        case .kitty:
            return "Kitty"
        case .terminal:
            return "Terminal.app"
        case .iTerm2:
            return "iTerm2"
        case .custom:
            return AppStrings.Terminals.customCommand
        }
    }

    var bundleIdentifier: String? {
        switch self {
        case .ghostty:
            return "com.mitchellh.ghostty"
        case .kitty:
            return "net.kovidgoyal.kitty"
        case .terminal:
            return "com.apple.Terminal"
        case .iTerm2:
            return "com.googlecode.iterm2"
        case .custom:
            return nil
        }
    }

    init?(bundleIdentifier: String) {
        switch bundleIdentifier.lowercased() {
        case "com.apple.terminal":
            self = .terminal
        case "com.googlecode.iterm2":
            self = .iTerm2
        case "net.kovidgoyal.kitty":
            self = .kitty
        case "com.mitchellh.ghostty":
            self = .ghostty
        default:
            return nil
        }
    }

    var defaultCommandTemplate: String {
        switch self {
        case .ghostty:
            return "open -a Ghostty {path}"
        case .kitty:
            return "open -a kitty --args --directory={path}"
        case .terminal:
            return "open -a Terminal {path}"
        case .iTerm2:
            return "open -a iTerm {path}"
        case .custom:
            return "open -a Terminal {path}"
        }
    }
}

/// Persisted as `~/Library/Application Support/Shellporter/config.json`.
/// All fields have defaults so the app works out of the box with no config file.
///
/// Hotkey codes are Carbon virtual key codes (not Unicode); modifiers are Carbon modifier masks.
/// Key code 17 = T, 8 = C. Modifier 2816 = controlKey | optionKey | cmdKey.
struct AppConfig: Codable, Equatable {
    var defaultTerminal: TerminalChoice
    var customCommandTemplate: String
    /// When true, Ghostty opens a new window (separate Space); may show an extra dock icon per window.
    var ghosttyOpenNewWindow: Bool
    var hotkeyKeyCode: UInt32
    var hotkeyModifiers: UInt32
    var copyCommandHotkeyKeyCode: UInt32
    var copyCommandHotkeyModifiers: UInt32

    static let defaultHotkeyKeyCode: UInt32 = 17 // T
    static let defaultHotkeyModifiers: UInt32 = UInt32(controlKey | optionKey | cmdKey)
    static let defaultCopyCommandHotkeyKeyCode: UInt32 = 8 // C
    static let defaultCopyCommandHotkeyModifiers: UInt32 = UInt32(controlKey | optionKey | cmdKey)

    static let `default` = AppConfig(
        defaultTerminal: .terminal,
        customCommandTemplate: TerminalChoice.terminal.defaultCommandTemplate,
        ghosttyOpenNewWindow: false,
        hotkeyKeyCode: defaultHotkeyKeyCode,
        hotkeyModifiers: defaultHotkeyModifiers,
        copyCommandHotkeyKeyCode: defaultCopyCommandHotkeyKeyCode,
        copyCommandHotkeyModifiers: defaultCopyCommandHotkeyModifiers
    )

    enum CodingKeys: String, CodingKey {
        case defaultTerminal
        case customCommandTemplate
        case ghosttyOpenNewWindow
        case hotkeyKeyCode
        case hotkeyModifiers
        case copyCommandHotkeyKeyCode
        case copyCommandHotkeyModifiers
    }

    init(
        defaultTerminal: TerminalChoice,
        customCommandTemplate: String,
        ghosttyOpenNewWindow: Bool,
        hotkeyKeyCode: UInt32,
        hotkeyModifiers: UInt32,
        copyCommandHotkeyKeyCode: UInt32,
        copyCommandHotkeyModifiers: UInt32
    ) {
        self.defaultTerminal = defaultTerminal
        self.customCommandTemplate = customCommandTemplate
        self.ghosttyOpenNewWindow = ghosttyOpenNewWindow
        self.hotkeyKeyCode = hotkeyKeyCode
        self.hotkeyModifiers = hotkeyModifiers
        self.copyCommandHotkeyKeyCode = copyCommandHotkeyKeyCode
        self.copyCommandHotkeyModifiers = copyCommandHotkeyModifiers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultTerminal = try container.decodeIfPresent(TerminalChoice.self, forKey: .defaultTerminal) ?? .terminal
        customCommandTemplate = try container.decodeIfPresent(String.self, forKey: .customCommandTemplate)
            ?? TerminalChoice.terminal.defaultCommandTemplate
        ghosttyOpenNewWindow = try container.decodeIfPresent(Bool.self, forKey: .ghosttyOpenNewWindow) ?? false
        hotkeyKeyCode = try container.decodeIfPresent(UInt32.self, forKey: .hotkeyKeyCode)
            ?? AppConfig.defaultHotkeyKeyCode
        hotkeyModifiers = try container.decodeIfPresent(UInt32.self, forKey: .hotkeyModifiers)
            ?? AppConfig.defaultHotkeyModifiers
        copyCommandHotkeyKeyCode = try container.decodeIfPresent(UInt32.self, forKey: .copyCommandHotkeyKeyCode)
            ?? AppConfig.defaultCopyCommandHotkeyKeyCode
        copyCommandHotkeyModifiers = try container.decodeIfPresent(UInt32.self, forKey: .copyCommandHotkeyModifiers)
            ?? AppConfig.defaultCopyCommandHotkeyModifiers
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(defaultTerminal, forKey: .defaultTerminal)
        try container.encode(customCommandTemplate, forKey: .customCommandTemplate)
        try container.encode(ghosttyOpenNewWindow, forKey: .ghosttyOpenNewWindow)
        try container.encode(hotkeyKeyCode, forKey: .hotkeyKeyCode)
        try container.encode(hotkeyModifiers, forKey: .hotkeyModifiers)
        try container.encode(copyCommandHotkeyKeyCode, forKey: .copyCommandHotkeyKeyCode)
        try container.encode(copyCommandHotkeyModifiers, forKey: .copyCommandHotkeyModifiers)
    }
}
