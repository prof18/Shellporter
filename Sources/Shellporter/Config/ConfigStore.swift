import Foundation

/// Loads, persists, and patches user configuration (`config.json`).
///
/// On first launch: auto-detects the system default terminal via `SystemTerminalDetector`.
/// On subsequent loads: if the configured terminal is no longer installed, silently falls
/// back to the detected or default terminal.
@MainActor
final class ConfigStore {
    private let logger: Logger
    private let fileManager: FileManager
    private let configURL: URL
    private let detectTerminal: () -> TerminalChoice?
    private let isTerminalInstalled: (TerminalChoice) -> Bool

    private(set) var config: AppConfig

    init(
        logger: Logger,
        fileManager: FileManager = .default,
        configURL: URL? = nil,
        detectTerminal: @escaping () -> TerminalChoice? = { SystemTerminalDetector.detectDefaultTerminalChoice() },
        isTerminalInstalled: @escaping (TerminalChoice) -> Bool = { SystemTerminalDetector.isInstalled($0) }
    ) {
        self.logger = logger
        self.fileManager = fileManager
        self.config = .default
        self.configURL = configURL ?? ConfigStore.makeConfigURL(fileManager: fileManager)
        self.detectTerminal = detectTerminal
        self.isTerminalInstalled = isTerminalInstalled
    }

    func load() {
        do {
            guard fileManager.fileExists(atPath: configURL.path) else {
                config = makeInitialConfig()
                try save()
                logger.log("Created default config at \(configURL.path)")
                return
            }

            let data = try Data(contentsOf: configURL)
            let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
            config = normalizeLoadedConfig(decoded)
            logger.log("Loaded config from \(configURL.path)")
        } catch {
            logger.log("Failed loading config (\(error.localizedDescription)); using defaults")
            config = makeInitialConfig()
        }
    }

    func update(_ transform: (inout AppConfig) -> Void) {
        var updatedConfig = config
        transform(&updatedConfig)
        guard updatedConfig != config else {
            return
        }
        config = updatedConfig
        do {
            try save()
            logger.log("Config updated")
        } catch {
            logger.log("Failed to save config: \(error.localizedDescription)")
        }
    }

    private func save() throws {
        let folderURL = configURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let data = try JSONEncoder.prettyPrinted.encode(config)
        try data.write(to: configURL, options: .atomic)
    }

    private static func makeConfigURL(fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport
            .appendingPathComponent("Shellporter", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    private func makeInitialConfig() -> AppConfig {
        var initial = AppConfig.default
        if let detected = detectTerminal() {
            initial.defaultTerminal = detected
            initial.customCommandTemplate = detected.defaultCommandTemplate
            logger.log("Detected system terminal handler: \(detected.displayName)")
        }
        return initial
    }

    private func normalizeLoadedConfig(_ loaded: AppConfig) -> AppConfig {
        guard !isTerminalInstalled(loaded.defaultTerminal) else {
            return loaded
        }

        var normalized = loaded
        let fallback = detectTerminal() ?? .terminal
        normalized.defaultTerminal = fallback
        logger.log(
            "Configured terminal unavailable; falling back to \(fallback.displayName)"
        )
        return normalized
    }
}

private extension JSONEncoder {
    static var prettyPrinted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
