import Testing
@testable import Shellporter

@Test
func settingsPresentation_hidesDiagnosticsWhenUnavailable() {
    let presentation = SettingsPresentation(
        config: .default,
        canCopyDiagnostics: false
    )

    #expect(!presentation.showsDiagnostics)
}

@Test
func settingsPresentation_showsDiagnosticsWhenAvailable() {
    let presentation = SettingsPresentation(
        config: .default,
        canCopyDiagnostics: true
    )

    #expect(presentation.showsDiagnostics)
}

@Test
func settingsPresentation_showsCustomCommandEditorOnlyForCustomTerminal() {
    var config = AppConfig.default
    config.defaultTerminal = .terminal

    #expect(!SettingsPresentation(config: config, canCopyDiagnostics: false).showsCustomCommandEditor)

    config.defaultTerminal = .custom

    #expect(SettingsPresentation(config: config, canCopyDiagnostics: false).showsCustomCommandEditor)
}

@Test
func settingsPresentation_showsGhosttyOptionOnlyForGhostty() {
    var config = AppConfig.default
    config.defaultTerminal = .terminal

    #expect(!SettingsPresentation(config: config, canCopyDiagnostics: false).showsGhosttyNewWindowOption)

    config.defaultTerminal = .ghostty

    #expect(SettingsPresentation(config: config, canCopyDiagnostics: false).showsGhosttyNewWindowOption)
}

@Test
func settingsPresentation_validatesCustomCommandPathPlaceholder() {
    var config = AppConfig.default

    config.customCommandTemplate = "open -a Terminal {path}"
    #expect(SettingsPresentation(config: config, canCopyDiagnostics: false).customCommandHasPathPlaceholder)

    config.customCommandTemplate = ""
    #expect(SettingsPresentation(config: config, canCopyDiagnostics: false).customCommandHasPathPlaceholder)

    config.customCommandTemplate = "open -a Terminal"
    #expect(!SettingsPresentation(config: config, canCopyDiagnostics: false).customCommandHasPathPlaceholder)
}
