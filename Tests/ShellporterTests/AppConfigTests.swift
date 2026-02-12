import Foundation
import Testing
@testable import Shellporter

@Test
func appConfig_decodesLegacyConfigWithoutOptionalFields() throws {
    let json = """
    {
      "defaultTerminal": "terminal",
      "customCommandTemplate": "open -a Terminal {path}",
      "hotkeyKeyCode": 17,
      "hotkeyModifiers": 4096
    }
    """
    let data = Data(json.utf8)
    let decoded = try JSONDecoder().decode(AppConfig.self, from: data)

    #expect(decoded.defaultTerminal == .terminal)
    #expect(decoded.customCommandTemplate == "open -a Terminal {path}")
    #expect(decoded.hotkeyKeyCode == 17)
    #expect(decoded.hotkeyModifiers == 4096)
    #expect(decoded.copyCommandHotkeyKeyCode == AppConfig.defaultCopyCommandHotkeyKeyCode)
    #expect(decoded.copyCommandHotkeyModifiers == AppConfig.defaultCopyCommandHotkeyModifiers)
}
