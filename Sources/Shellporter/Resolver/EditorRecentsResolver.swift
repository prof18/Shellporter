import Foundation

/// Resolves the current project path by reading VS Code / Cursor / Antigravity `storage.json`.
///
/// These editors store recently opened workspaces in `~/Library/Application Support/<Editor>/User/globalStorage/storage.json`.
/// The resolver uses two extraction methods:
/// 1. **JSON traversal**: parse the JSON and walk recursively to find `history.recentlyOpenedPathsList.entries`.
/// 2. **Regex fallback**: scan raw text for `file:///` URIs and absolute paths (handles malformed JSON or schema changes).
///
/// Matching: exact folder-name match against window title hints first, then partial, then most recent.
enum EditorRecentsResolver {
    static func resolve(
        ideFamily: IDEFamily,
        windowTitle: String?,
        fileManager: FileManager = .default,
        searchRoots: [URL]? = nil
    ) -> URL? {
        let roots = searchRoots ?? defaultSearchRoots(for: ideFamily)
        guard !roots.isEmpty else { return nil }

        let hints = PathHeuristics.projectNameHints(from: windowTitle)
        let paths = candidatePaths(from: roots, fileManager: fileManager)
        guard !paths.isEmpty else { return nil }

        if !hints.isEmpty {
            if let exact = paths.first(where: { path in
                let name = URL(fileURLWithPath: path).lastPathComponent.lowercased()
                return hints.contains(name)
            }) {
                return URL(fileURLWithPath: exact)
            }

            if let partial = paths.first(where: { path in
                let name = URL(fileURLWithPath: path).lastPathComponent.lowercased()
                return hints.contains(where: { name.contains($0) || $0.contains(name) })
            }) {
                return URL(fileURLWithPath: partial)
            }
        }

        return URL(fileURLWithPath: paths[0])
    }

    private static func defaultSearchRoots(for ideFamily: IDEFamily) -> [URL] {
        let home = NSHomeDirectory()
        switch ideFamily {
        case .vscode:
            return [
                URL(fileURLWithPath: "\(home)/Library/Application Support/Code/User/globalStorage", isDirectory: true),
                URL(fileURLWithPath: "\(home)/Library/Application Support/Code - Insiders/User/globalStorage", isDirectory: true),
                URL(fileURLWithPath: "\(home)/Library/Application Support/VSCodium/User/globalStorage", isDirectory: true),
            ]
        case .cursor:
            return [
                URL(fileURLWithPath: "\(home)/Library/Application Support/Cursor/User/globalStorage", isDirectory: true),
            ]
        case .antigravity:
            return [
                URL(fileURLWithPath: "\(home)/Library/Application Support/Antigravity/User/globalStorage", isDirectory: true),
            ]
        default:
            return []
        }
    }

    private static func candidatePaths(from roots: [URL], fileManager: FileManager) -> [String] {
        let storageFiles = roots
            .map { $0.appendingPathComponent("storage.json") }
            .filter { fileManager.fileExists(atPath: $0.path) }
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return lhsDate > rhsDate
            }

        var orderedPaths: [String] = []
        var seen = Set<String>()
        for fileURL in storageFiles {
            guard let data = try? Data(contentsOf: fileURL) else {
                continue
            }

            let text = String(data: data, encoding: .utf8) ?? ""
            let extractedPaths = extractRecentPathsFromJSON(data) + extractPathsByRegex(from: text)
            for path in extractedPaths {
                if let normalized = PathHeuristics.normalizeProjectPath(
                    from: URL(fileURLWithPath: path),
                    fileManager: fileManager
                ) {
                    let normalizedPath = normalized.path
                    if seen.insert(normalizedPath).inserted {
                        orderedPaths.append(normalizedPath)
                    }
                }
            }
        }

        return orderedPaths
    }

    private static let fileURIRegex = try? NSRegularExpression(pattern: #"file:///[^"\\]+"#)
    private static let absolutePathRegex = try? NSRegularExpression(pattern: #"/[A-Za-z0-9._/\- ]+"#)

    private static func extractRecentPathsFromJSON(_ data: Data) -> [String] {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }

        let entries = findRecentEntries(in: jsonObject)
        guard !entries.isEmpty else { return [] }

        var results: [String] = []
        for entry in entries {
            if let path = extractPath(from: entry) {
                results.append(path)
            }
        }
        return results
    }

    private static func findRecentEntries(in value: Any) -> [[String: Any]] {
        if let dict = value as? [String: Any] {
            if let history = dict["history.recentlyOpenedPathsList"] as? [String: Any],
               let entries = history["entries"] as? [[String: Any]],
               !entries.isEmpty {
                return entries
            }

            for (key, nestedValue) in dict {
                if (key.localizedCaseInsensitiveContains("recentlyOpenedPathsList")
                    || key.localizedCaseInsensitiveContains("openedPathsList")),
                   let nested = nestedValue as? [String: Any],
                   let entries = nested["entries"] as? [[String: Any]],
                   !entries.isEmpty {
                    return entries
                }
            }

            for nestedValue in dict.values {
                let entries = findRecentEntries(in: nestedValue)
                if !entries.isEmpty {
                    return entries
                }
            }
        } else if let array = value as? [Any] {
            for item in array {
                let entries = findRecentEntries(in: item)
                if !entries.isEmpty {
                    return entries
                }
            }
        }
        return []
    }

    private static func extractPath(from entry: [String: Any]) -> String? {
        let uriKeys = ["folderUri", "workspaceUri", "fileUri", "uri"]
        for key in uriKeys {
            if let raw = entry[key] as? String, let decoded = decodePathToken(raw) {
                return decoded
            }
        }

        let directPathKeys = ["folder", "workspace", "path", "fsPath"]
        for key in directPathKeys {
            if let raw = entry[key] as? String, let decoded = decodePathToken(raw) {
                return decoded
            }
        }

        return nil
    }

    /// VS Code storage uses various URI encodings: `\u002F` (unicode escape for `/`),
    /// `\/` (JSON-escaped slash), `file://` prefix. Normalize all of them to plain paths.
    private static func decodePathToken(_ rawValue: String) -> String? {
        let normalizedRaw = rawValue
            .replacingOccurrences(of: "\\u002F", with: "/")
            .replacingOccurrences(of: "\\/", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

        if normalizedRaw.hasPrefix("file://"), let url = URL(string: normalizedRaw) {
            return url.path
        }
        if normalizedRaw.hasPrefix("/") {
            return normalizedRaw
        }
        if normalizedRaw.hasPrefix("~") {
            return NSString(string: normalizedRaw).expandingTildeInPath
        }
        return nil
    }

    private static func extractPathsByRegex(from text: String) -> [String] {
        let regexes = [fileURIRegex, absolutePathRegex].compactMap { $0 }

        var results: [String] = []
        for regex in regexes {
            let matches = regex.matches(
                in: text,
                options: [],
                range: NSRange(location: 0, length: text.utf16.count)
            )
            for match in matches {
                guard let range = Range(match.range, in: text) else { continue }
                var raw = String(text[range])
                raw = raw.replacingOccurrences(of: "\\u002F", with: "/")
                raw = raw.replacingOccurrences(of: "\\/", with: "/")
                raw = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

                if raw.hasPrefix("file://"), let url = URL(string: raw) {
                    results.append(url.path)
                } else {
                    results.append(raw)
                }
            }
        }
        return results
    }
}
