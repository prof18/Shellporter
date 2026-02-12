import Foundation

/// LRU cache mapping (bundleID + window title) -> project path. Persisted as JSON.
///
/// ## Why a cache?
///
/// Live resolution strategies (AX APIs, title parsing, XML/JSON metadata) can fail transiently:
///
/// - The Accessibility API returns nil during app launch or window transitions (the window
///   exists but its attributes aren't populated yet).
/// - Window titles change when switching tabs (e.g. VS Code shows the file name, losing the
///   workspace name), so title-based strategies lose their signal.
/// - JetBrains `recentProjects.xml` and VS Code `storage.json` are only updated on project
///   open/close, not continuously -- if the file hasn't been flushed yet, parsing finds nothing.
/// - Apps the resolver doesn't recognize (`IDEFamily.unknown`) only have AXDocument and title
///   parsing. If neither works, there's nothing to fall back on without a cache.
///
/// The cache turns a previous successful resolution into a reliable fallback. Once Shellporter
/// resolves a project path for an app/window combination, the answer is remembered and can
/// be returned instantly even if every live strategy fails on the next invocation.
///
/// It also covers the "same project, quick re-invocation" case: parsing XML/JSON on every
/// hotkey press is wasteful when the user is working in the same project for hours.
///
/// ## Dual-key strategy
///
/// Every successful resolution writes **two** cache entries:
///
/// - **Exact key** `<bundleID>|title|<normalized title>`: precise recall when the same window
///   title is seen again. Handles multi-project setups (e.g. two IntelliJ windows with
///   different project names in the title).
/// - **Last key** `<bundleID>|last`: fallback when the title has changed or is empty. Covers
///   the common case where a user works in one project per editor and the title content varies
///   (e.g. after switching files).
///
/// Lookup tries the exact key first (higher confidence), then the last key.
///
/// ## Staleness protection
///
/// Cached paths are validated against the filesystem: `lookup()` checks `fileExists` before
/// returning, and `load()` prunes entries whose paths no longer exist. This prevents stale
/// cache hits after a project is moved or deleted.
///
/// Evicts oldest entries (by `lastUsed` date) when the 200-entry limit is exceeded.
@MainActor
final class ResolutionCacheStore {
    private let logger: Logger
    private let fileManager: FileManager
    private let cacheURL: URL
    private var cache: [String: CacheEntry] = [:]

    static let maxEntries = 200

    struct CacheEntry: Codable {
        let path: String
        let lastUsed: Date
    }

    init(
        logger: Logger,
        fileManager: FileManager = .default,
        cacheURL: URL? = nil
    ) {
        self.logger = logger
        self.fileManager = fileManager
        self.cacheURL = cacheURL ?? ResolutionCacheStore.makeCacheURL(fileManager: fileManager)
        load()
    }

    var entryCount: Int { cache.count }

    func record(bundleIdentifier: String, windowTitle: String?, path: URL) {
        let standardized = path.standardizedFileURL.path
        let now = Date()
        cache[lastKey(bundleIdentifier: bundleIdentifier)] = CacheEntry(path: standardized, lastUsed: now)
        if let normalizedTitle = normalizeTitle(windowTitle), !normalizedTitle.isEmpty {
            cache[exactKey(bundleIdentifier: bundleIdentifier, normalizedTitle: normalizedTitle)] = CacheEntry(path: standardized, lastUsed: now)
        }
        evictIfNeeded()
        save()
    }

    func lookup(bundleIdentifier: String, windowTitle: String?) -> URL? {
        if let normalizedTitle = normalizeTitle(windowTitle), !normalizedTitle.isEmpty {
            let key = exactKey(bundleIdentifier: bundleIdentifier, normalizedTitle: normalizedTitle)
            if let entry = cache[key], fileManager.fileExists(atPath: entry.path) {
                return URL(fileURLWithPath: entry.path)
            }
        }

        let last = lastKey(bundleIdentifier: bundleIdentifier)
        if let entry = cache[last], fileManager.fileExists(atPath: entry.path) {
            return URL(fileURLWithPath: entry.path)
        }
        return nil
    }

    // MARK: - Persistence

    private func load() {
        guard fileManager.fileExists(atPath: cacheURL.path) else {
            cache = [:]
            return
        }

        do {
            let data = try Data(contentsOf: cacheURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            if let decoded = try? decoder.decode([String: CacheEntry].self, from: data) {
                cache = decoded
            } else {
                // Migrate from legacy [String: String] format
                let legacy = try JSONDecoder().decode([String: String].self, from: data)
                let now = Date()
                cache = legacy.mapValues { CacheEntry(path: $0, lastUsed: now) }
                logger.log("Resolution cache: migrated \(legacy.count) entries from legacy format.")
            }
        } catch {
            logger.log("Resolution cache load failed: \(error.localizedDescription)")
            cache = [:]
            return
        }

        pruneStaleEntries()
    }

    private func pruneStaleEntries() {
        let before = cache.count
        cache = cache.filter { fileManager.fileExists(atPath: $0.value.path) }
        let pruned = before - cache.count
        if pruned > 0 {
            logger.log("Resolution cache: pruned \(pruned) stale entries.")
            save()
        }
    }

    private func evictIfNeeded() {
        guard cache.count > Self.maxEntries else { return }
        let sorted = cache.sorted { $0.value.lastUsed < $1.value.lastUsed }
        let toDrop = cache.count - Self.maxEntries
        for (key, _) in sorted.prefix(toDrop) {
            cache.removeValue(forKey: key)
        }
        logger.log("Resolution cache: evicted \(toDrop) oldest entries.")
    }

    private func save() {
        do {
            let folderURL = cacheURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(cache)
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            logger.log("Resolution cache save failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Keys

    private func normalizeTitle(_ title: String?) -> String? {
        title?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func exactKey(bundleIdentifier: String, normalizedTitle: String) -> String {
        "\(bundleIdentifier.lowercased())|title|\(normalizedTitle)"
    }

    private func lastKey(bundleIdentifier: String) -> String {
        "\(bundleIdentifier.lowercased())|last"
    }

    private static func makeCacheURL(fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport
            .appendingPathComponent("Shellporter", isDirectory: true)
            .appendingPathComponent("resolution-cache.json")
    }
}
