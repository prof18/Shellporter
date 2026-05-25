# Changelog

## 0.1.3

- Open Ghostty new-window launches through Ghostty 1.3+ AppleScript support so new windows stay in the existing app instance without an extra Dock icon
- Keep a compatibility fallback for older Ghostty versions or disabled AppleScript support

## 0.1.2

- Fix Ghostty launch fallback when macOS CLI `+new-window` exits with an error

## 0.1.1

- Add open at login option
- Update about screen

## 0.1.0

- Initial release
- Open a terminal in the active IDE project folder with a global hotkey
- IDE support: JetBrains family, Android Studio, VS Code, VSCodium, Cursor, Xcode
- Terminal support: Terminal.app, iTerm2, Kitty, Ghostty, custom command
- Smart project path resolution via accessibility, title heuristics, and IDE recents
- Global shortcuts for opening terminal and copying `cd` command
- Menu bar app with preferences for terminal selection, hotkey customization, and diagnostics
- Auto-update support via Sparkle
