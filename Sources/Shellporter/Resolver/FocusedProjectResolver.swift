import AppKit
import Foundation

/// Orchestrates project path resolution by running an IDE-family-specific chain of strategies.
///
/// The pipeline: snapshot the AX window -> run strategies in order -> first success wins -> cache it.
/// Non-cached strategies run on a background queue (file I/O heavy); cache lookup stays on @MainActor
/// because ResolutionCacheStore is actor-isolated.
@MainActor
final class FocusedProjectResolver {
    private let logger: Logger
    private let cacheStore: ResolutionCacheStore
    /// Background queue for file-I/O-heavy strategies (JetBrains XML, VS Code JSON, disk checks).
    private let resolveQueue = DispatchQueue(label: "com.shellporter.resolver.io", qos: .userInitiated)

    init(
        logger: Logger,
        cacheStore: ResolutionCacheStore
    ) {
        self.logger = logger
        self.cacheStore = cacheStore
    }

    func resolve(targetApp: NSRunningApplication? = nil) async -> ResolvedProjectContext {
        let app = targetApp ?? NSWorkspace.shared.frontmostApplication
        guard let app else {
            return ResolvedProjectContext(
                appName: "Unknown",
                bundleIdentifier: "unknown",
                ideFamily: .unknown,
                projectPath: nil,
                source: "none",
                details: "No frontmost application.",
                attempts: [],
                windowTitle: nil,
                documentValue: nil,
                windowSource: nil
            )
        }

        let appName = app.localizedName ?? "Unknown"
        let bundleID = app.bundleIdentifier ?? "unknown"
        let ideFamily = IDEFamily.from(bundleIdentifier: bundleID)
        let snapshot = AXWindowInspector.snapshot(pid: app.processIdentifier, promptForAccess: false)
        var attempts: [ResolverAttempt] = []

        if !snapshot.trusted {
            let message = "Accessibility permission missing."
            attempts.append(
                ResolverAttempt(
                    strategy: "Accessibility",
                    success: false,
                    details: message,
                    candidatePath: nil
                )
            )
            let unresolved = makeUnresolvedContext(
                appName: appName,
                bundleID: bundleID,
                ideFamily: ideFamily,
                details: message,
                attempts: attempts,
                snapshot: snapshot
            )
            log(context: unresolved)
            return unresolved
        }

        let strategyOrder = strategySequence(for: ideFamily)
        let nonCachedStrategies = strategyOrder.filter { $0 != .cachedResolution }
        let nonCachedResolution = await runNonCachedStrategies(
            strategies: nonCachedStrategies,
            snapshot: snapshot,
            ideFamily: ideFamily
        )
        attempts.append(contentsOf: nonCachedResolution.attempts)
        if let successfulStrategy = nonCachedResolution.successfulStrategy,
           let successfulAttempt = attempts.last,
           successfulAttempt.success,
           let path = successfulAttempt.candidatePath {
            // Record every successful live resolution so the cache can serve as fallback
            // when live strategies fail transiently on future invocations.
            cacheStore.record(bundleIdentifier: bundleID, windowTitle: snapshot.title, path: path)
            let context = ResolvedProjectContext(
                appName: appName,
                bundleIdentifier: bundleID,
                ideFamily: ideFamily,
                projectPath: path,
                source: successfulStrategy.displayName,
                details: successfulAttempt.details,
                attempts: attempts,
                windowTitle: snapshot.title,
                documentValue: snapshot.document,
                windowSource: snapshot.windowSource
            )
            log(context: context)
            return context
        }

        // All live strategies failed. Fall back to the cache: if we've successfully resolved
        // this app/window before, reuse that path. This handles transient AX failures, title
        // changes mid-session, and apps the resolver doesn't deeply understand.
        // See ResolutionCacheStore for the full rationale on why the cache exists.
        if strategyOrder.contains(.cachedResolution) {
            let cachedAttempt: ResolverAttempt
            if let path = cacheStore.lookup(bundleIdentifier: bundleID, windowTitle: snapshot.title) {
                cachedAttempt = ResolverAttempt(
                    strategy: ResolverStrategy.cachedResolution.displayName,
                    success: true,
                    details: "Resolved using cached path from previous successful launch.",
                    candidatePath: path
                )
            } else {
                cachedAttempt = ResolverAttempt(
                    strategy: ResolverStrategy.cachedResolution.displayName,
                    success: false,
                    details: "No cached path for this app/window signature.",
                    candidatePath: nil
                )
            }
            attempts.append(cachedAttempt)
            if cachedAttempt.success, let path = cachedAttempt.candidatePath {
                cacheStore.record(bundleIdentifier: bundleID, windowTitle: snapshot.title, path: path)
                let context = ResolvedProjectContext(
                    appName: appName,
                    bundleIdentifier: bundleID,
                    ideFamily: ideFamily,
                    projectPath: path,
                    source: ResolverStrategy.cachedResolution.displayName,
                    details: cachedAttempt.details,
                    attempts: attempts,
                    windowTitle: snapshot.title,
                    documentValue: snapshot.document,
                    windowSource: snapshot.windowSource
                )
                log(context: context)
                return context
            }
        }

        let unresolved = makeUnresolvedContext(
            appName: appName,
            bundleID: bundleID,
            ideFamily: ideFamily,
            details: "No resolver strategy produced a valid path.",
            attempts: attempts,
            snapshot: snapshot
        )
        log(context: unresolved)
        return unresolved
    }

    private func runNonCachedStrategies(
        strategies: [ResolverStrategy],
        snapshot: AXWindowSnapshot,
        ideFamily: IDEFamily
    ) async -> NonCachedResolutionResult {
        return await withCheckedContinuation { continuation in
            resolveQueue.async {
                var attempts: [ResolverAttempt] = []
                var successfulStrategy: ResolverStrategy?

                for strategy in strategies {
                    let attempt = strategy.run(
                        snapshot: snapshot,
                        ideFamily: ideFamily,
                        fileManager: .default
                    )
                    attempts.append(attempt)
                    if attempt.success {
                        successfulStrategy = strategy
                        break
                    }
                }

                continuation.resume(
                    returning: NonCachedResolutionResult(
                        attempts: attempts,
                        successfulStrategy: successfulStrategy
                    )
                )
            }
        }
    }

    private func makeUnresolvedContext(
        appName: String,
        bundleID: String,
        ideFamily: IDEFamily,
        details: String,
        attempts: [ResolverAttempt],
        snapshot: AXWindowSnapshot
    ) -> ResolvedProjectContext {
        ResolvedProjectContext(
            appName: appName,
            bundleIdentifier: bundleID,
            ideFamily: ideFamily,
            projectPath: nil,
            source: "none",
            details: details,
            attempts: attempts,
            windowTitle: snapshot.title,
            documentValue: snapshot.document,
            windowSource: snapshot.windowSource
        )
    }

    /// Each IDE family gets a different strategy order based on which data source is most
    /// reliable for that editor:
    ///
    /// - **JetBrains**: Title first -- window title always contains the project name, while
    ///   AXDocument points to a single file (not the project root). Recents XML is the fallback.
    /// - **VS Code / Cursor / Antigravity**: AXDocument first -- exposes the workspace URI directly.
    /// - **Xcode**: AXDocument first -- usually points to the open file, title as fallback.
    /// - **Unknown**: Generic order; AXDocument is the best general-purpose signal.
    ///
    /// Cache is always last: live data is preferred (it reflects the current state), but when
    /// live strategies fail transiently the cache provides a reliable answer from a previous
    /// successful resolution. See `ResolutionCacheStore` for the full rationale.
    private func strategySequence(for family: IDEFamily) -> [ResolverStrategy] {
        switch family {
        case .jetBrains:
            return [.titlePaths, .jetBrainsRecentProjects, .axDocument, .cachedResolution]
        case .vscode, .cursor, .antigravity:
            return [.axDocument, .titlePaths, .editorRecents, .cachedResolution]
        case .xcode:
            return [.axDocument, .titlePaths, .cachedResolution]
        case .unknown:
            return [.axDocument, .titlePaths, .cachedResolution]
        }
    }

    private func log(context: ResolvedProjectContext) {
        let path = context.projectPath?.path ?? "unresolved"
        let titleSuffix = context.windowTitle.map { " title=\"\($0)\"" } ?? ""
        logger.log(
            "Resolver[\(context.ideFamily.rawValue)] \(context.bundleIdentifier) -> \(path) via \(context.source) windowSource=\(context.windowSource ?? "-")\(titleSuffix)"
        )
        for attempt in context.attempts {
            let pathText = attempt.candidatePath?.path ?? "-"
            logger.log("  attempt[\(attempt.strategy)] success=\(attempt.success) path=\(pathText) details=\(attempt.details)")
        }
    }

    private struct NonCachedResolutionResult {
        let attempts: [ResolverAttempt]
        let successfulStrategy: ResolverStrategy?
    }
}

/// Individual resolution strategies. Each knows how to extract a project path from a single
/// data source. They are stateless functions called by FocusedProjectResolver in chain order.
private enum ResolverStrategy {
    /// Read the file path from the Accessibility API's AXDocument attribute.
    case axDocument
    /// Parse the window title for path-like tokens (separators, embedded paths, ~ expansion).
    case titlePaths
    /// Parse JetBrains `recentProjects.xml` files with tiered scoring.
    case jetBrainsRecentProjects
    /// Parse VS Code/Cursor `storage.json` for recently opened workspaces.
    case editorRecents
    /// LRU cache fallback (handled on @MainActor, not the resolver queue).
    case cachedResolution

    var displayName: String {
        switch self {
        case .axDocument:
            return "AXDocument"
        case .titlePaths:
            return "AXTitle"
        case .jetBrainsRecentProjects:
            return "JetBrainsRecentProjects"
        case .editorRecents:
            return "EditorRecents"
        case .cachedResolution:
            return "CachedResolution"
        }
    }

    func run(
        snapshot: AXWindowSnapshot,
        ideFamily: IDEFamily,
        fileManager: FileManager
    ) -> ResolverAttempt {
        switch self {
        case .axDocument:
            return resolveUsingAXDocument(snapshot: snapshot, fileManager: fileManager)
        case .titlePaths:
            return resolveUsingTitle(snapshot: snapshot, fileManager: fileManager)
        case .jetBrainsRecentProjects:
            return resolveUsingJetBrainsRecents(snapshot: snapshot, ideFamily: ideFamily, fileManager: fileManager)
        case .editorRecents:
            return resolveUsingEditorRecents(snapshot: snapshot, ideFamily: ideFamily, fileManager: fileManager)
        case .cachedResolution:
            return ResolverAttempt(
                strategy: displayName,
                success: false,
                details: "Skipped: cache lookup is handled on the main actor.",
                candidatePath: nil
            )
        }
    }

    private func resolveUsingAXDocument(snapshot: AXWindowSnapshot, fileManager: FileManager) -> ResolverAttempt {
        guard let rawDocument = snapshot.document, !rawDocument.isEmpty else {
            return ResolverAttempt(
                strategy: displayName,
                success: false,
                details: "No AXDocument value on selected window.",
                candidatePath: nil
            )
        }

        let rawURL: URL
        if rawDocument.hasPrefix("file://"), let parsed = URL(string: rawDocument) {
            rawURL = parsed
        } else {
            rawURL = URL(fileURLWithPath: rawDocument)
        }

        guard let normalized = PathHeuristics.normalizeProjectPath(from: rawURL, fileManager: fileManager) else {
            return ResolverAttempt(
                strategy: displayName,
                success: false,
                details: "AXDocument present but path does not exist on disk.",
                candidatePath: nil
            )
        }

        return ResolverAttempt(
            strategy: displayName,
            success: true,
            details: "Resolved from selected window AXDocument.",
            candidatePath: normalized
        )
    }

    private func resolveUsingTitle(snapshot: AXWindowSnapshot, fileManager: FileManager) -> ResolverAttempt {
        guard let title = snapshot.title, !title.isEmpty else {
            return ResolverAttempt(
                strategy: displayName,
                success: false,
                details: "No selected window title available.",
                candidatePath: nil
            )
        }

        let candidates = PathHeuristics.titlePathCandidates(from: title)
        guard !candidates.isEmpty else {
            return ResolverAttempt(
                strategy: displayName,
                success: false,
                details: "No path-like tokens in title.",
                candidatePath: nil
            )
        }

        for candidate in candidates {
            if let normalized = PathHeuristics.normalizeProjectPath(from: candidate, fileManager: fileManager) {
                return ResolverAttempt(
                    strategy: displayName,
                    success: true,
                    details: "Resolved by parsing a title path candidate.",
                    candidatePath: normalized
                )
            }
        }

        return ResolverAttempt(
            strategy: displayName,
            success: false,
            details: "Title had path candidates, but none existed on disk.",
            candidatePath: nil
        )
    }

    private func resolveUsingJetBrainsRecents(
        snapshot: AXWindowSnapshot,
        ideFamily: IDEFamily,
        fileManager: FileManager
    ) -> ResolverAttempt {
        guard ideFamily == .jetBrains else {
            return ResolverAttempt(
                strategy: displayName,
                success: false,
                details: "Skipped: strategy only applies to JetBrains IDEs.",
                candidatePath: nil
            )
        }

        guard let path = JetBrainsRecentProjectsResolver.resolve(
            windowTitle: snapshot.title,
            fileManager: fileManager
        ) else {
            return ResolverAttempt(
                strategy: displayName,
                success: false,
                details: "No candidate found in recentProjects.xml files.",
                candidatePath: nil
            )
        }

        return ResolverAttempt(
            strategy: displayName,
            success: true,
            details: "Resolved using JetBrains recent projects metadata.",
            candidatePath: path
        )
    }

    private func resolveUsingEditorRecents(
        snapshot: AXWindowSnapshot,
        ideFamily: IDEFamily,
        fileManager: FileManager
    ) -> ResolverAttempt {
        guard ideFamily == .vscode || ideFamily == .cursor || ideFamily == .antigravity else {
            return ResolverAttempt(
                strategy: displayName,
                success: false,
                details: "Skipped: strategy only applies to VS Code/Cursor/Antigravity families.",
                candidatePath: nil
            )
        }

        guard let path = EditorRecentsResolver.resolve(
            ideFamily: ideFamily,
            windowTitle: snapshot.title,
            fileManager: fileManager
        ) else {
            return ResolverAttempt(
                strategy: displayName,
                success: false,
                details: "No candidate found in editor recents metadata.",
                candidatePath: nil
            )
        }

        return ResolverAttempt(
            strategy: displayName,
            success: true,
            details: "Resolved using VS Code/Cursor recent workspace metadata.",
            candidatePath: path
        )
    }
}
