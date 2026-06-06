struct SettingsPresentation: Equatable {
    let showsGhosttyNewWindowOption: Bool
    let showsITerm2NewWindowOption: Bool
    let showsCustomCommandEditor: Bool
    let showsDiagnostics: Bool
    let customCommandHasPathPlaceholder: Bool

    init(config: AppConfig, canCopyDiagnostics: Bool) {
        showsGhosttyNewWindowOption = config.defaultTerminal == .ghostty
        showsITerm2NewWindowOption = config.defaultTerminal == .iTerm2
        showsCustomCommandEditor = config.defaultTerminal == .custom
        showsDiagnostics = canCopyDiagnostics
        customCommandHasPathPlaceholder = config.customCommandTemplate.isEmpty
            || config.customCommandTemplate.contains("{path}")
    }
}
