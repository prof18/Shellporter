import Foundation

/// Classifies the frontmost app into an IDE family. Each family gets a different resolver
/// strategy chain because each editor exposes project path data differently.
enum IDEFamily: String {
    case jetBrains = "jetbrains"
    case vscode = "vscode"
    case cursor = "cursor"
    case antigravity = "antigravity"
    case xcode = "xcode"
    case unknown = "unknown"

    static func from(bundleIdentifier: String) -> IDEFamily {
        let bundle = bundleIdentifier.lowercased()
        if isJetBrainsBundle(bundle) {
            return .jetBrains
        }
        if bundle == "com.microsoft.vscode" || bundle == "com.microsoft.vscodeinsiders" || bundle == "com.vscodium" {
            return .vscode
        }
        if bundle.contains("cursor") || bundle == "com.todesktop.230313mzl4w4u92" {
            return .cursor
        }
        if bundle == "com.google.antigravity" {
            return .antigravity
        }
        if bundle == "com.apple.dt.xcode" {
            return .xcode
        }
        return .unknown
    }

    private static func isJetBrainsBundle(_ bundle: String) -> Bool {
        bundle.hasPrefix("com.jetbrains.")
            || bundle.hasPrefix("org.jetbrains.")
            || bundle.hasPrefix("com.intellij.")
            || bundle.hasPrefix("com.google.android.studio")
    }
}

/// One step in the resolver chain. Recorded for diagnostics -- the user can copy all
/// attempts to pasteboard via the menu for debugging failed resolutions.
struct ResolverAttempt {
    let strategy: String
    let success: Bool
    let details: String
    let candidatePath: URL?
}

/// The final output of a resolution attempt. Contains the resolved path (if any),
/// which strategy succeeded, and the full list of attempts for diagnostics.
struct ResolvedProjectContext {
    let appName: String
    let bundleIdentifier: String
    let ideFamily: IDEFamily
    let projectPath: URL?
    let source: String
    let details: String
    let attempts: [ResolverAttempt]
    let windowTitle: String?
    let documentValue: String?
    let windowSource: String?

    var diagnosticsSummary: String {
        var lines: [String] = []
        lines.append("App: \(appName)")
        lines.append("Bundle: \(bundleIdentifier)")
        lines.append("IDE Family: \(ideFamily.rawValue)")
        lines.append("Resolved: \(projectPath?.path ?? "no")")
        lines.append("Source: \(source)")
        lines.append("Details: \(details)")
        if let windowTitle {
            lines.append("Window Title: \(windowTitle)")
        }
        if let documentValue {
            lines.append("AXDocument: \(documentValue)")
        }
        if let windowSource {
            lines.append("Window Source: \(windowSource)")
        }
        lines.append("Attempts:")
        if attempts.isEmpty {
            lines.append("- (none)")
        } else {
            for attempt in attempts {
                let status = attempt.success ? "ok" : "fail"
                let path = attempt.candidatePath?.path ?? "-"
                lines.append("- [\(status)] \(attempt.strategy) path=\(path) details=\(attempt.details)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
