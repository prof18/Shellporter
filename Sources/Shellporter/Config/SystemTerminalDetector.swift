import AppKit
import Foundation
import UniformTypeIdentifiers

enum SystemTerminalDetector {
    static func detectDefaultTerminalChoice() -> TerminalChoice? {
        let contentTypes: [UTType] = [
            UTType("public.shell-script"),
            UTType("public.unix-executable"),
            UTType("com.apple.terminal.shell-script"),
        ].compactMap { $0 }

        let workspace = NSWorkspace.shared
        for contentType in contentTypes {
            guard let appURL = workspace.urlForApplication(toOpen: contentType) else {
                continue
            }
            if let bundle = Bundle(url: appURL),
               let bundleID = bundle.bundleIdentifier,
               let choice = TerminalChoice(bundleIdentifier: bundleID) {
                return choice
            }
        }

        return nil
    }

    static func isInstalled(_ terminal: TerminalChoice) -> Bool {
        guard let bundleID = terminal.bundleIdentifier else {
            return true
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }
}
