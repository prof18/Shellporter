import Foundation
import Testing
@testable import Shellporter

@Suite(.serialized)
struct ConfigStoreTests {
    private let fileManager = FileManager.default

    private func makeTempConfigURL() -> URL {
        let dir = fileManager.temporaryDirectory
            .appendingPathComponent("shellporter-tests-\(UUID().uuidString)", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }

    private func cleanup(_ url: URL) {
        try? fileManager.removeItem(at: url.deletingLastPathComponent())
    }

    @MainActor
    private func makeStore(configURL: URL) -> ConfigStore {
        ConfigStore(
            logger: Logger(),
            configURL: configURL,
            detectTerminal: { nil },
            isTerminalInstalled: { _ in true }
        )
    }

    @Test @MainActor
    func load_missingFileCreatesDefaults() throws {
        let url = makeTempConfigURL()
        defer { cleanup(url) }

        let store = makeStore(configURL: url)
        store.load()

        #expect(store.config.defaultTerminal == AppConfig.default.defaultTerminal)
        #expect(fileManager.fileExists(atPath: url.path))
    }

    @Test @MainActor
    func loadSaveRoundTrip() throws {
        let url = makeTempConfigURL()
        defer { cleanup(url) }

        let store = makeStore(configURL: url)
        store.load()

        store.update { config in
            config.customCommandTemplate = "my-terminal {path}"
        }

        let store2 = makeStore(configURL: url)
        store2.load()

        #expect(store2.config.customCommandTemplate == "my-terminal {path}")
    }

    @Test @MainActor
    func load_corruptJSONFallsBackToDefaults() throws {
        let url = makeTempConfigURL()
        defer { cleanup(url) }

        let dir = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json at all {{{".utf8).write(to: url)

        let store = makeStore(configURL: url)
        store.load()

        #expect(store.config.hotkeyKeyCode == AppConfig.defaultHotkeyKeyCode)
        #expect(store.config.hotkeyModifiers == AppConfig.defaultHotkeyModifiers)
    }
}
