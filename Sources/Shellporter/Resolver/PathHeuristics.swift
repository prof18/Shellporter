import Foundation

/// Pure-function utilities for extracting and normalizing file paths from window titles and AX values.
///
/// Two main jobs:
/// 1. **Title parsing**: extract path-like tokens from IDE window titles (separators, regex, tilde expansion).
/// 2. **Path normalization**: given a raw file/directory URL, walk up to the project root
///    (`.git`, `.xcworkspace`, etc.) and strip Xcode bundle suffixes.
enum PathHeuristics {
    /// Normalize a raw URL to a project root directory.
    /// File URLs -> parent directory. `.xcodeproj`/`.xcworkspace` -> parent. Then walk up for VCS markers.
    static func normalizeProjectPath(from rawURL: URL, fileManager: FileManager = .default) -> URL? {
        let standardized = rawURL.standardizedFileURL
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: standardized.path, isDirectory: &isDirectory) else {
            return nil
        }

        let existingPath = isDirectory.boolValue ? standardized : standardized.deletingLastPathComponent()
        let baseDirectory = normalizeContainerDirectory(existingPath)
        if let detectedRoot = findProjectRoot(startingAt: baseDirectory, fileManager: fileManager) {
            return detectedRoot
        }
        return baseDirectory
    }

    static func projectNameHints(from title: String?) -> [String] {
        guard let title, !title.isEmpty else { return [] }
        let separators = [" — ", " – ", " - "]
        var candidates: [String] = [title]
        for separator in separators where title.contains(separator) {
            candidates.append(contentsOf: title.components(separatedBy: separator))
        }
        return candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && !$0.contains("/") && $0.count > 1 }
    }

    /// Extract path candidates from a window title string. Tries three approaches in order:
    /// 1. Split on common title separators (` -- `, ` - `, ` - `) used by Electron and JetBrains.
    /// 2. Token scan for words starting with `/` or `~`.
    /// 3. Regex for embedded paths in brackets, e.g. `[~/Workspace/foo]`.
    static func titlePathCandidates(from title: String) -> [URL] {
        var candidates: [URL] = []

        // Most Electron/JetBrains/Xcode title patterns include separators.
        let separators = [" — ", " – ", " - "]
        for separator in separators where title.contains(separator) {
            for component in title.components(separatedBy: separator) {
                appendCandidateIfPathLike(component, into: &candidates)
            }
        }

        // Fallback token scan.
        for token in title.split(separator: " ") where token.hasPrefix("/") || token.hasPrefix("~") {
            appendCandidateIfPathLike(String(token), into: &candidates)
        }

        // Embedded path scan for bracketed/title-mixed patterns, e.g.
        // "FeedFlow [~/Workspace/feedflow/feed-flow] – file.kt [FeedFlow]".
        for embedded in embeddedPathTokens(in: title) {
            appendCandidateIfPathLike(embedded, into: &candidates)
        }

        return deduplicate(candidates)
    }

    private static func appendCandidateIfPathLike(_ rawValue: String, into candidates: inout [URL]) {
        let cleaned = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`()[]{}<>.,;"))
        guard !cleaned.isEmpty else { return }
        guard cleaned.hasPrefix("/") || cleaned.hasPrefix("~") else { return }

        let expanded = NSString(string: cleaned).expandingTildeInPath
        candidates.append(URL(fileURLWithPath: expanded))
    }

    private static func deduplicate(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var deduped: [URL] = []
        for url in urls {
            let path = url.standardizedFileURL.path
            if seen.insert(path).inserted {
                deduped.append(url)
            }
        }
        return deduped
    }

    private static let embeddedPathRegex = try? NSRegularExpression(pattern: #"(~|/)[A-Za-z0-9._/\-]+"#)

    private static func embeddedPathTokens(in title: String) -> [String] {
        guard let regex = embeddedPathRegex else { return [] }

        let matches = regex.matches(
            in: title,
            options: [],
            range: NSRange(location: 0, length: title.utf16.count)
        )

        return matches.compactMap { match in
            guard let range = Range(match.range, in: title) else { return nil }
            let value = String(title[range])
            return value.count > 1 ? value : nil
        }
    }

    /// Strip `.xcodeproj` / `.xcworkspace` bundle suffixes -- these are directories on disk
    /// and we want the terminal to open in the parent, not inside the Xcode bundle.
    private static func normalizeContainerDirectory(_ directory: URL) -> URL {
        let ext = directory.pathExtension.lowercased()
        if ext == "xcodeproj" || ext == "xcworkspace" {
            return directory.deletingLastPathComponent()
        }
        return directory
    }

    /// Walk up the directory tree looking for VCS markers (.git, .hg, .svn) or IDE workspace files.
    /// Returns the first (deepest) match, not the topmost -- avoids going to monorepo root.
    private static func findProjectRoot(startingAt directory: URL, fileManager: FileManager) -> URL? {
        var current = directory.standardizedFileURL
        while true {
            if isProjectRoot(at: current, fileManager: fileManager) {
                return current
            }
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent.path == current.path {
                return nil
            }
            current = parent
        }
    }

    private static let vcsMarkers: Set<String> = [".git", ".hg", ".svn"]

    private static func isProjectRoot(at directory: URL, fileManager: FileManager) -> Bool {
        for marker in vcsMarkers {
            if fileManager.fileExists(atPath: directory.appendingPathComponent(marker).path) {
                return true
            }
        }

        guard let children = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        return children.contains { child in
            let ext = child.pathExtension.lowercased()
            return ext == "xcworkspace" || ext == "xcodeproj" || ext == "code-workspace"
        }
    }
}
