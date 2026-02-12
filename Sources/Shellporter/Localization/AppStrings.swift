import Foundation

enum AppStrings {
    // MARK: - Terminals
    enum Terminals {
        static let customCommand = Localization.localized("terminals-custom-command")
    }

    // MARK: - Menu
    enum Menu {
        static let accessibilityMissing = Localization.localized("menu-accessibility-missing")
        static let requestAccessibilityPermission = Localization.localized("menu-request-accessibility-permission")
        static let openAccessibilitySettings = Localization.localized("menu-open-accessibility-settings")
        static let openTerminalInCurrentProject = Localization.localized("menu-open-terminal-in-current-project")
        static let focusTerminalAndCopyCommand = Localization.localized("menu-focus-terminal-copy-command")
        static let focusTerminalAndCopyCommandHint = Localization.localized("menu-focus-terminal-copy-command-hint")
        static let openWith = Localization.localized("menu-open-with")
        static let aboutShellporter = Localization.localized("menu-about-shellporter")
        static let preferences = Localization.localized("menu-preferences")
        static let checkForUpdates = Localization.localized("menu-check-for-updates")
        static let quitShellporter = Localization.localized("menu-quit-shellporter")
    }

    // MARK: - About
    enum About {
        static let description = Localization.localized("about-description")
        static let versionFormat = Localization.localized("about-version-format")
        static let github = Localization.localized("about-link-github")
        static let website = Localization.localized("about-link-website")
        static let twitter = Localization.localized("about-link-twitter")
        static let githubURL = "https://github.com/prof18/shellporter"
        static let websiteURL = "https://github.com/prof18/shellporter"
        static let twitterURL = "https://x.com/prof18"
    }

    // MARK: - Settings
    enum Settings {
        static let sectionDefaultTerminal = Localization.localized("settings-section-default-terminal")
        static let fieldTerminal = Localization.localized("settings-field-terminal")
        static let ghosttyOpenNewWindow = Localization.localized("settings-ghostty-open-new-window")
        static let ghosttyOpenNewWindowHint = Localization.localized("settings-ghostty-open-new-window-hint")
        static let sectionCustomTerminalCommand = Localization.localized("settings-section-custom-terminal-command")
        static let customCommandDescription = Localization.localized("settings-custom-command-description")
        static let fieldTemplate = Localization.localized("settings-field-template")
        static let customCommandHint = Localization.localized("settings-custom-command-hint")
        static let customCommandMissingPathWarning = Localization.localized("settings-custom-command-missing-path-warning")
        static let sectionAccessibility = Localization.localized("settings-section-accessibility")
        static let accessibilityStatus = Localization.localized("settings-accessibility-status")
        static let accessibilityGranted = Localization.localized("settings-accessibility-granted")
        static let accessibilityMissing = Localization.localized("settings-accessibility-missing")
        static let accessibilityOpenSettings = Localization.localized("settings-accessibility-open-settings")
        static let accessibilityRefreshStatus = Localization.localized("settings-accessibility-refresh-status")
        static let accessibilityHint = Localization.localized("settings-accessibility-hint")
        static let sectionGlobalShortcuts = Localization.localized("settings-section-global-shortcuts")
        static let openTerminalShortcut = Localization.localized("settings-open-terminal-shortcut")
        static let focusTerminalCopyShortcut = Localization.localized("settings-focus-terminal-copy-shortcut")
        static let cancel = Localization.localized("settings-cancel")
        static let resetDefault = Localization.localized("settings-reset-default")
        static let focusTerminalCopyHint = Localization.localized("settings-focus-terminal-copy-hint")
        static let hotkeyCaptureHint = Localization.localized("settings-hotkey-capture-hint")
        static let sectionDiagnostics = Localization.localized("settings-section-diagnostics")
        static let copyLastResolutionDiagnostics = Localization.localized("settings-copy-last-resolution-diagnostics")
        static let diagnosticsHint = Localization.localized("settings-diagnostics-hint")
        static let hotkeyErrorModifierRequired = Localization.localized("settings-hotkey-error-modifier-required")
        static let hotkeyErrorUnsupportedKey = Localization.localized("settings-hotkey-error-unsupported-key")
        static let pressShortcut = Localization.localized("settings-press-shortcut")
        static let recordShortcut = Localization.localized("settings-record-shortcut")
    }

    // MARK: - Alerts
    enum Alerts {
        static let projectPathNotFoundTitle = Localization.localized("alerts-project-path-not-found-title")
        static let projectPathNotFoundMessage = Localization.localized("alerts-project-path-not-found-message")
        static let failedToLaunchTerminalTitle = Localization.localized("alerts-failed-to-launch-terminal-title")
        static let selectProjectFolderTitle = Localization.localized("alerts-select-project-folder-title")
        static let selectProjectFolderMessage = Localization.localized("alerts-select-project-folder-message")
        static let openTerminalPrompt = Localization.localized("alerts-open-terminal-prompt")
    }

    // MARK: - Onboarding
    enum Onboarding {
        static let title = Localization.localized("onboarding-title")
        static let description = Localization.localized("onboarding-description")
        static let openSystemSettings = Localization.localized("onboarding-open-system-settings")
        static let quit = Localization.localized("onboarding-quit")
    }

    // MARK: - Window
    enum Window {
        static let preferencesTitle = Localization.localized("window-preferences-title")
        static let onboardingTitle = Localization.localized("window-onboarding-title")
        static let aboutTitle = Localization.localized("window-about-title")
    }

    // MARK: - Status Bar
    enum StatusBar {
        static let fallbackTitle = Localization.localized("status-bar-fallback-title")
        static let tooltipDefault = Localization.localized("status-bar-tooltip-default")
        static let tooltipAccessibilityMissing = Localization.localized("status-bar-tooltip-accessibility-missing")
        static let symbolAccessibilityDescription = Localization.localized("status-bar-symbol-accessibility-description")
    }

    // MARK: - Terminal Launcher
    enum TerminalLauncher {
        static let invalidCustomCommand = Localization.localized("terminal-launcher-invalid-custom-command")
        static let appleScriptExecutionFailed = Localization.localized("terminal-launcher-apple-script-execution-failed")
    }
}

private enum Localization {
    static func localized(_ key: String) -> String {
        NSLocalizedString(
            key,
            tableName: "Localizable",
            bundle: .module,
            value: key,
            comment: ""
        )
    }
}
