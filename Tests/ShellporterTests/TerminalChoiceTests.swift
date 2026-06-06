import Testing
@testable import Shellporter

@Test
func availableChoices_hidesUnavailableBundleBackedTerminals() {
    let available = TerminalChoice.availableChoices { terminal in
        terminal == .terminal || terminal == .custom
    }

    #expect(available == [.terminal, .custom])
}

@Test
func availableChoices_keepsCustomCommandAvailable() {
    let available = TerminalChoice.availableChoices { terminal in
        terminal.bundleIdentifier == nil
    }

    #expect(available == [.custom])
}

@Test
func availableAppChoices_excludesCustomCommand() {
    let available = TerminalChoice.availableAppChoices { terminal in
        terminal == .terminal || terminal == .custom
    }

    #expect(available == [.terminal])
}
