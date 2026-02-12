import Foundation

enum TerminalLauncherError: LocalizedError {
    case invalidCustomCommand

    var errorDescription: String? {
        switch self {
        case .invalidCustomCommand:
            return AppStrings.TerminalLauncher.invalidCustomCommand
        }
    }
}

/// Opens a terminal app at a given directory. Each terminal type has distinct launch mechanics:
///
/// - **Terminal.app / iTerm2**: AppleScript via `osascript` (slow but reliable; the only way to
///   script these apps). iTerm2 additionally supports session reuse via name-based markers.
/// - **Kitty / Ghostty**: CLI binary launch (fast, no AppleScript). Searches known install paths
///   and falls back to `open -a` if the binary isn't found.
/// - **Custom**: User-provided shell command template with `{path}` substitution.
final class TerminalLauncher {
    private let logger: Logger
    /// AppleScript output reading blocks; do it off-main to avoid stalling the UI.
    private let scriptQueue = DispatchQueue(label: "com.shellporter.applescript", qos: .userInitiated)
    /// iTerm2 sessions are tagged with this prefix + path. On re-invocation, we scan for a matching
    /// session and select it instead of creating a duplicate tab.
    private static let sessionTitlePrefix = "shellporter:"
    private static let kittyExecutableCandidates = [
        "/Applications/kitty.app/Contents/MacOS/kitty",
        "/opt/homebrew/bin/kitty",
        "/usr/local/bin/kitty",
        "/usr/bin/kitty",
    ]
    /// Ghostty CLI (Kitty-style: talk to running instance, new window, one dock icon).
    /// On macOS, `+new-window` / `--working-directory` are not fully supported yet (ghostty-org/ghostty#2353);
    /// we try anyway and fall back to `open -a` / `open -na`.
    private static let ghosttyExecutableCandidates = [
        "/Applications/Ghostty.app/Contents/MacOS/Ghostty",
        "/opt/homebrew/bin/ghostty",
        "/usr/local/bin/ghostty",
    ]

    init(logger: Logger) {
        self.logger = logger
    }

    func launch(at path: URL, choice: TerminalChoice, config: AppConfig) throws {
        switch choice {
        case .ghostty:
            if config.ghosttyOpenNewWindow {
                // New window (separate Space); may show an extra dock icon per window.
                try launchProcess(
                    executable: "/usr/bin/open",
                    arguments: ["-na", "Ghostty", "--args", "--working-directory=\(path.path)"]
                )
            } else {
                // Prefer Kitty-style CLI so one instance = one dock icon, new window at path (when Ghostty supports it).
                if try launchGhosttySingleInstance(path: path) {
                    break
                }
                // Fallback: reuse running instance and open a new tab at path (no extra dock icon).
                // With multiple Ghostty instances, macOS picks one (typically the frontmost); we don't control which.
                try launchProcess(
                    executable: "/usr/bin/open",
                    arguments: ["-a", "Ghostty", path.path]
                )
            }
        case .kitty:
            if try launchKittySingleInstance(path: path) {
                break
            }
            try launchProcess(
                executable: "/usr/bin/open",
                arguments: ["-a", "kitty", "--args", "--directory=\(path.path)"]
            )
        case .terminal:
            try launchTerminalApp(path: path)
        case .iTerm2:
            try launchITerm(path: path)
        case .custom:
            let template = config.customCommandTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !template.isEmpty else {
                throw TerminalLauncherError.invalidCustomCommand
            }
            let command = template.replacingOccurrences(of: "{path}", with: path.path.shellEscapedForBash())
            try launchProcess(
                executable: "/bin/zsh",
                arguments: ["-lc", command]
            )
        }
        logger.log("Launched \(choice.displayName) for \(path.path)")
    }

    private func launchProcess(executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
    }

    private func launchKittySingleInstance(path: URL) throws -> Bool {
        let fileManager = FileManager.default
        guard let executable = Self.kittyExecutableCandidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) else {
            logger.log("Kitty executable not found in known locations; using open fallback.")
            return false
        }

        do {
            try launchProcess(
                executable: executable,
                arguments: ["--single-instance", "--directory=\(path.path)"]
            )
            return true
        } catch {
            logger.log("Kitty single-instance launch failed (\(error.localizedDescription)); using open fallback.")
            return false
        }
    }

    /// Try Ghostty CLI (like Kitty): ask running instance to open a new window at path (one dock icon).
    /// On macOS this is not fully supported yet; we try and fall back to `open -a Ghostty path` (new tab).
    private func launchGhosttySingleInstance(path: URL) throws -> Bool {
        let fileManager = FileManager.default
        guard let executable = Self.ghosttyExecutableCandidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) else {
            logger.log("Ghostty executable not found in known locations; using open fallback.")
            return false
        }

        do {
            try launchProcess(
                executable: executable,
                arguments: ["+new-window", "--working-directory=\(path.path)"]
            )
            return true
        } catch {
            logger.log("Ghostty single-instance launch failed (\(error.localizedDescription)); using open fallback.")
            return false
        }
    }

    private func launchTerminalApp(path: URL) throws {
        try runAppleScriptIgnoringOutput(Self.terminalLaunchScript(path: path))
    }

    /// AppleScript for Terminal.app. Two paths:
    /// - Already running: `do script "cd ..."` opens a new tab.
    /// - Cold start: `reopen`, wait for the window (up to 2s), then run in front window.
    static func terminalLaunchScript(path: URL) -> [String] {
        let command = "cd \(path.path.shellEscapedForBash())"
        let escapedCommand = command.appleScriptEscaped()
        return [
            "tell application \"Terminal\"",
            "if application \"Terminal\" is running then",
            "do script \"\(escapedCommand)\"",
            "else",
            "reopen",
            "set waitAttempts to 0",
            "repeat while ((count of windows) = 0 and waitAttempts < 40)",
            "delay 0.05",
            "set waitAttempts to waitAttempts + 1",
            "end repeat",
            "if (count of windows) > 0 then",
            "do script \"\(escapedCommand)\" in front window",
            "else",
            "do script \"\(escapedCommand)\"",
            "end if",
            "end if",
            "activate",
            "end tell",
        ]
    }

    private func launchITerm(path: URL) throws {
        let marker = Self.sessionTitlePrefix + path.standardizedFileURL.path
        if try reuseITermSession(marker: marker) {
            logger.log("Reused iTerm2 window for \(path.path)")
            return
        }

        let command = "cd \(path.path.shellEscapedForBash())"
        try runAppleScriptIgnoringOutput([
            "tell application \"iTerm2\"",
            "activate",
            "if (count of windows) > 0 then",
            "tell current window",
            "set newTab to (create tab with default profile command \"\(command.appleScriptEscaped())\")",
            "set name of current session of newTab to \"\(marker.appleScriptEscaped())\"",
            "end tell",
            "else",
            "set newWindow to (create window with default profile command \"\(command.appleScriptEscaped())\")",
            "set name of current session of newWindow to \"\(marker.appleScriptEscaped())\"",
            "end if",
            "end tell",
        ])
    }

    private func reuseITermSession(marker: String) throws -> Bool {
        let output = try runAppleScriptAndCapture([
            "tell application \"iTerm2\"",
            "if not running then return \"not-running\"",
            "repeat with w in windows",
            "repeat with t in tabs of w",
            "repeat with s in sessions of t",
            "if name of s is \"\(marker.appleScriptEscaped())\" then",
            "set current window to w",
            "select t",
            "select s",
            "activate",
            "return \"reused\"",
            "end if",
            "end repeat",
            "end repeat",
            "end repeat",
            "return \"not-found\"",
            "end tell",
        ])
        return output == "reused"
    }

    private func runAppleScriptIgnoringOutput(_ lines: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = lines.flatMap { ["-e", $0] }
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()

        var errorText = ""
        scriptQueue.sync {
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            errorText = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        guard process.terminationStatus == 0 else {
            logger.log(
                "AppleScript failed with exit code \(process.terminationStatus): \(errorText.isEmpty ? "-" : errorText)"
            )
            throw NSError(
                domain: "Shellporter.AppleScript",
                code: Int(process.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey: errorText.isEmpty
                        ? AppStrings.TerminalLauncher.appleScriptExecutionFailed
                        : errorText,
                ]
            )
        }
    }

    private func runAppleScriptAndCapture(_ lines: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = lines.flatMap { ["-e", $0] }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()

        // Run blocking wait on background queue to avoid stalling main thread.
        var outputText = ""
        var capturedError: Error?
        scriptQueue.sync {
            // Read pipe data before waitUntilExit to avoid deadlock if output fills the pipe buffer.
            let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            outputText = String(data: outputData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let errorText = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if process.terminationStatus != 0 {
                capturedError = NSError(
                    domain: "Shellporter.AppleScript",
                    code: Int(process.terminationStatus),
                    userInfo: [
                        NSLocalizedDescriptionKey: errorText.isEmpty
                            ? AppStrings.TerminalLauncher.appleScriptExecutionFailed
                            : errorText,
                    ]
                )
            }
        }

        if let capturedError { throw capturedError }
        return outputText
    }

}

extension String {
    /// Wraps in single quotes with proper escaping: `'` -> `'"'"'`. This is the safest
    /// way to pass arbitrary paths to bash without injection risk.
    func shellEscapedForBash() -> String {
        if isEmpty {
            return "''"
        }
        return "'" + replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    func appleScriptEscaped() -> String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}
