import Foundation

/// Resolves the current project path by parsing JetBrains IDE `recentProjects.xml` files.
///
/// JetBrains stores recent project metadata in `~/Library/Application Support/JetBrains/*/options/`
/// (and `~/Library/Application Support/Google/*/options/` for Android Studio). Each XML file contains
/// `<entry key="path">` elements with optional `RecentProjectMetaInfo` metadata (frame title,
/// opened status, timestamps).
///
/// A **tiered scoring** system matches candidates against the current window title to pick the
/// right project when multiple similar ones exist (e.g. `feed-flow` vs `feed-flow-2`):
///
/// - Tier 0: Frame title matches window title AND mentions the candidate path (strongest)
/// - Tier 1: Folder name exactly matches a title hint
/// - Tier 2: Frame title contains the full candidate path
/// - Tier 3: Partial/substring name overlap (weakest)
///
/// Within a tier, candidates are ordered by: opened > lastOpened > activation time > open time > source rank > depth.
enum JetBrainsRecentProjectsResolver {
    static func resolve(
        windowTitle: String?,
        fileManager: FileManager = .default,
        searchRoots: [URL]? = nil
    ) -> URL? {
        let titleHints = PathHeuristics.projectNameHints(from: windowTitle)
        let candidates = candidateEntries(fileManager: fileManager, searchRoots: searchRoots)
        let uniquePaths = Array(Set(candidates.map(\.path))).sorted()
        guard !uniquePaths.isEmpty else { return nil }

        if titleHints.isEmpty {
            return uniquePaths.count == 1 ? URL(fileURLWithPath: uniquePaths[0]) : nil
        }

        if let best = bestMatchingCandidate(candidates: candidates, titleHints: titleHints, windowTitle: windowTitle) {
            return URL(fileURLWithPath: best.path)
        }

        return uniquePaths.count == 1 ? URL(fileURLWithPath: uniquePaths[0]) : nil
    }

    private static func bestMatchingCandidate(
        candidates: [RecentProjectCandidate],
        titleHints: [String],
        windowTitle: String?
    ) -> RecentProjectCandidate? {
        let normalizedWindowTitle = windowTitle?.lowercased()
        let canonicalHints = titleHints.map(canonicalToken).filter { !$0.isEmpty }

        // Candidates are assigned to the best tier they qualify for (lower = stronger match).
        // Exact name match from the current window title (Tier 1) outranks stale "frame contains path"
        // metadata (Tier 2) so we pick the project the user is actually in (e.g. feed-flow over feed-flow-2).
        var scored: [(candidate: RecentProjectCandidate, tier: Int)] = []

        for candidate in candidates {
            let pathName = URL(fileURLWithPath: candidate.path).lastPathComponent.lowercased()
            let canonicalPathName = canonicalToken(pathName)
            let frameTitle = candidate.frameTitle

            // Tier 0: Frame title exactly matches the current window title and mentions this candidate's path.
            // (Without path check, another project's stale frame title could match the current window.)
            if let frameTitle, let normalizedWindowTitle, frameTitle == normalizedWindowTitle,
               frameTitleMentionsCandidatePath(frameTitle: frameTitle, candidatePath: candidate.path) {
                scored.append((candidate, 0))
                continue
            }

            // Tier 1: Folder name exactly matches a title hint (literal or canonical).
            // Current window title is the source of truth; prefer it over stored frame metadata.
            let hasExactMatch = titleHints.contains(where: { $0 == pathName })
                || canonicalHints.contains(where: { !$0.isEmpty && $0 == canonicalPathName })
            if hasExactMatch {
                scored.append((candidate, 1))
                continue
            }

            // Tier 2: Frame title contains the candidate's full path (stale but useful when no exact name).
            if frameTitleMentionsCandidatePath(frameTitle: frameTitle, candidatePath: candidate.path) {
                scored.append((candidate, 2))
                continue
            }

            // Tier 3: Partial/substring folder name overlap with a title hint.
            let hasPartialMatch = titleHints.contains(where: {
                pathName.contains($0) || $0.contains(pathName)
            })
            if hasPartialMatch {
                scored.append((candidate, 3))
                continue
            }
        }

        guard !scored.isEmpty else { return nil }

        return scored
            .sorted { lhs, rhs in
                if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
                return preferredCandidateOrder(lhs.candidate, rhs.candidate)
            }
            .first?
            .candidate
    }

    private static func candidateEntries(fileManager: FileManager, searchRoots: [URL]?) -> [RecentProjectCandidate] {
        let roots = searchRoots ?? defaultSearchRoots()

        var urls: [URL] = []
        for rootURL in roots {
            guard fileManager.fileExists(atPath: rootURL.path) else { continue }

            if let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles],
                errorHandler: nil
            ) {
                for case let fileURL as URL in enumerator {
                    if fileURL.lastPathComponent == "recentProjects.xml" {
                        urls.append(fileURL)
                    }
                }
            }
        }

        let datedURLs = urls.map { fileURL -> (URL, Date) in
            let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
            return (fileURL, values?.contentModificationDate ?? .distantPast)
        }

        let orderedURLs = datedURLs.sorted { lhs, rhs in
            if lhs.1 != rhs.1 {
                return lhs.1 > rhs.1
            }
            return lhs.0.path > rhs.0.path
        }

        var candidates: [RecentProjectCandidate] = []
        var seen = Set<String>()
        for (rank, datedURL) in orderedURLs.enumerated() {
            let url = datedURL.0
            let fileRank = orderedURLs.count - rank
            guard let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8) else {
                continue
            }

            for parsed in parseEntryMetadata(from: text) {
                let normalizedPath = normalize(pathToken: parsed.pathToken)
                guard fileManager.fileExists(atPath: normalizedPath) else { continue }
                let standardizedPath = URL(fileURLWithPath: normalizedPath).standardizedFileURL.path
                let key = "\(standardizedPath)|\(parsed.frameTitle ?? "")|\(parsed.isLastOpened)|\(fileRank)"
                guard seen.insert(key).inserted else { continue }

                candidates.append(
                    RecentProjectCandidate(
                        path: standardizedPath,
                        frameTitle: parsed.frameTitle,
                        isLastOpened: parsed.isLastOpened,
                        isOpened: parsed.isOpened,
                        activationTimestamp: parsed.activationTimestamp,
                        projectOpenTimestamp: parsed.projectOpenTimestamp,
                        sourceRank: fileRank
                    )
                )
            }
        }

        return candidates
    }

    // MARK: - Cached Regex Patterns

    private static let metaInfoEntryRegex = try? NSRegularExpression(
        pattern: #"(?s)<entry\s+key=\"([^\"]+)\"[^>]*>\s*<value>\s*<RecentProjectMetaInfo([^>]*)>(.*?)</RecentProjectMetaInfo>\s*</value>\s*</entry>"#
    )
    private static let bareEntryRegex = try? NSRegularExpression(
        pattern: #"<entry\s+key=\"([^\"]+)\"[^>]*/?>"#
    )
    private static let frameTitleRegex = try? NSRegularExpression(
        pattern: #"frameTitle=\"([^\"]+)\""#
    )
    private static let lastOpenedRegex = try? NSRegularExpression(
        pattern: #"<option\s+name=\"lastOpenedProject\"\s+value=\"([^\"]+)\""#
    )
    private static let activationTimestampRegex = try? NSRegularExpression(
        pattern: #"<option\s+name="activationTimestamp"\s+value="([0-9]+)""#
    )
    private static let projectOpenTimestampRegex = try? NSRegularExpression(
        pattern: #"<option\s+name="projectOpenTimestamp"\s+value="([0-9]+)""#
    )

    private static func parseEntryMetadata(from text: String) -> [ParsedEntry] {
        var entries: [ParsedEntry] = []
        var seenKeys = Set<String>()

        if let regex = metaInfoEntryRegex {
            let matches = regex.matches(
                in: text,
                options: [],
                range: NSRange(location: 0, length: text.utf16.count)
            )
            for match in matches {
                guard
                    let pathRange = Range(match.range(at: 1), in: text),
                    let attrsRange = Range(match.range(at: 2), in: text),
                    let bodyRange = Range(match.range(at: 3), in: text)
                else {
                    continue
                }

                let pathToken = String(text[pathRange])
                let attrs = String(text[attrsRange])
                let body = String(text[bodyRange])
                let frameTitle = extractFrameTitle(from: attrs)
                let isOpened = attrs.contains("opened=\"true\"")
                let activationTimestamp = extractOptionTimestamp(name: "activationTimestamp", from: body)
                let projectOpenTimestamp = extractOptionTimestamp(name: "projectOpenTimestamp", from: body)
                seenKeys.insert(pathToken)
                entries.append(
                    ParsedEntry(
                        pathToken: pathToken,
                        frameTitle: frameTitle,
                        isLastOpened: false,
                        isOpened: isOpened,
                        activationTimestamp: activationTimestamp,
                        projectOpenTimestamp: projectOpenTimestamp
                    )
                )
            }
        }

        if let entryRegex = bareEntryRegex {
            let matches = entryRegex.matches(
                in: text,
                options: [],
                range: NSRange(location: 0, length: text.utf16.count)
            )
            for match in matches {
                guard let keyRange = Range(match.range(at: 1), in: text) else { continue }
                let pathToken = String(text[keyRange])
                guard !seenKeys.contains(pathToken) else { continue }
                seenKeys.insert(pathToken)
                entries.append(
                    ParsedEntry(
                        pathToken: pathToken,
                        frameTitle: nil,
                        isLastOpened: false,
                        isOpened: false,
                        activationTimestamp: 0,
                        projectOpenTimestamp: 0
                    )
                )
            }
        }

        if let lastOpened = extractLastOpenedProject(from: text) {
            entries.append(
                ParsedEntry(
                    pathToken: lastOpened,
                    frameTitle: nil,
                    isLastOpened: true,
                    isOpened: false,
                    activationTimestamp: 0,
                    projectOpenTimestamp: 0
                )
            )
        }

        return entries
    }

    private static func extractFrameTitle(from attributes: String) -> String? {
        guard let regex = frameTitleRegex,
              let match = regex.firstMatch(
                in: attributes,
                options: [],
                range: NSRange(location: 0, length: attributes.utf16.count)
              ),
              let range = Range(match.range(at: 1), in: attributes) else {
            return nil
        }
        return String(attributes[range]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func extractLastOpenedProject(from text: String) -> String? {
        guard let regex = lastOpenedRegex,
        let match = regex.firstMatch(
            in: text,
            options: [],
            range: NSRange(location: 0, length: text.utf16.count)
        ),
        let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractOptionTimestamp(name: String, from body: String) -> Int64 {
        let regex: NSRegularExpression?
        switch name {
        case "activationTimestamp": regex = activationTimestampRegex
        case "projectOpenTimestamp": regex = projectOpenTimestampRegex
        default: regex = try? NSRegularExpression(
            pattern: #"<option\s+name=\""# + NSRegularExpression.escapedPattern(for: name) + #"\"\s+value=\"([0-9]+)\""#
        )
        }
        guard let regex,
              let match = regex.firstMatch(
                  in: body,
                  options: [],
                  range: NSRange(location: 0, length: body.utf16.count)
              ),
              let range = Range(match.range(at: 1), in: body) else {
            return 0
        }
        return Int64(body[range]) ?? 0
    }

    /// JetBrains XML uses `$USER_HOME$` (or its XML entity form `&#36;USER_HOME&#36;`)
    /// as a placeholder for the home directory. Expand it and strip URI/quote wrappers.
    private static func normalize(pathToken: String) -> String {
        var value = pathToken
            .replacingOccurrences(of: "$USER_HOME$", with: NSHomeDirectory())
            .replacingOccurrences(of: "&#36;USER_HOME&#36;", with: NSHomeDirectory())
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'<>"))

        if value.hasPrefix("file://"), let url = URL(string: value) {
            value = url.path
        }

        return value
    }

    private static func preferredCandidateOrder(_ lhs: RecentProjectCandidate, _ rhs: RecentProjectCandidate) -> Bool {
        if lhs.isOpened != rhs.isOpened {
            return lhs.isOpened
        }
        if lhs.isLastOpened != rhs.isLastOpened {
            return lhs.isLastOpened
        }
        if lhs.activationTimestamp != rhs.activationTimestamp {
            return lhs.activationTimestamp > rhs.activationTimestamp
        }
        if lhs.projectOpenTimestamp != rhs.projectOpenTimestamp {
            return lhs.projectOpenTimestamp > rhs.projectOpenTimestamp
        }
        if lhs.sourceRank != rhs.sourceRank {
            return lhs.sourceRank > rhs.sourceRank
        }
        if lhs.depth != rhs.depth {
            return lhs.depth > rhs.depth
        }
        return lhs.path > rhs.path
    }

    /// Strip non-alphanumeric chars for fuzzy matching: "my-project" and "myproject" compare equal.
    private static func canonicalToken(_ input: String) -> String {
        input.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func frameTitleMentionsCandidatePath(frameTitle: String?, candidatePath: String) -> Bool {
        guard let frameTitle else { return false }
        let normalizedFrame = frameTitle
            .replacingOccurrences(of: "~", with: NSHomeDirectory())
            .lowercased()
        let normalizedPath = candidatePath.lowercased()
        return normalizedFrame.contains(normalizedPath)
    }

    private static func defaultSearchRoots() -> [URL] {
        let home = NSHomeDirectory()
        return [
            URL(fileURLWithPath: "\(home)/Library/Application Support/JetBrains", isDirectory: true),
            URL(fileURLWithPath: "\(home)/Library/Application Support/Google", isDirectory: true),
        ]
    }

    private struct ParsedEntry {
        let pathToken: String
        let frameTitle: String?
        let isLastOpened: Bool
        let isOpened: Bool
        let activationTimestamp: Int64
        let projectOpenTimestamp: Int64
    }

    private struct RecentProjectCandidate {
        let path: String
        let frameTitle: String?
        let isLastOpened: Bool
        let isOpened: Bool
        let activationTimestamp: Int64
        let projectOpenTimestamp: Int64
        let sourceRank: Int

        var depth: Int {
            URL(fileURLWithPath: path).pathComponents.count
        }
    }
}
