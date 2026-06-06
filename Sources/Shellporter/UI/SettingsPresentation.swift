struct SettingsPresentation: Equatable {
    let showsGhosttyNewWindowOption: Bool
    let showsCustomCommandEditor: Bool
    let showsDiagnostics: Bool
    let customCommandHasPathPlaceholder: Bool

    init(config: AppConfig, canCopyDiagnostics: Bool) {
        showsGhosttyNewWindowOption = config.defaultTerminal == .ghostty
        showsCustomCommandEditor = config.defaultTerminal == .custom
        showsDiagnostics = canCopyDiagnostics
        customCommandHasPathPlaceholder = config.customCommandTemplate.isEmpty
            || config.customCommandTemplate.contains("{path}")
    }
}
