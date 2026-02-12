import Foundation
import Testing
@testable import Shellporter

@Test
func titlePathCandidates_extractsUnixPathSegments() {
    let title = "api-service — /Users/dev/Workspace/feedflow/feed-flow — Cursor"
    let candidates = PathHeuristics.titlePathCandidates(from: title).map(\.path)
    #expect(candidates.contains("/Users/dev/Workspace/feedflow/feed-flow"))
}

@Test
func titlePathCandidates_extractsBracketedTildePathSegments() {
    let title = "FeedFlow [~/Workspace/feedflow/feed-flow] – flatpak-build-setup.sh [FeedFlow]"
    let candidates = PathHeuristics.titlePathCandidates(from: title).map(\.path)
    let expected = URL(fileURLWithPath: "\(NSHomeDirectory())/Workspace/feedflow/feed-flow").path
    #expect(candidates.contains(expected))
}

@Test
func normalizeProjectPath_prefersAncestorWithProjectMarker() throws {
    let fileManager = FileManager.default
    let base = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let projectRoot = base.appendingPathComponent("demo", isDirectory: true)
    let nested = projectRoot.appendingPathComponent("Sources/App", isDirectory: true)
    let sourceFile = nested.appendingPathComponent("Main.swift")

    try fileManager.createDirectory(at: nested, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: projectRoot.appendingPathComponent(".git"), withIntermediateDirectories: true)
    try Data().write(to: sourceFile)
    try Data().write(to: projectRoot.appendingPathComponent("Package.swift"))

    let normalized = PathHeuristics.normalizeProjectPath(from: sourceFile, fileManager: fileManager)
    #expect(normalized?.path == projectRoot.path)
}

@Test
func normalizeProjectPath_findsGitRootAboveGradleProject() throws {
    let fileManager = FileManager.default
    let base = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let workspaceRoot = base.appendingPathComponent("feedflow", isDirectory: true)
    let androidProject = workspaceRoot.appendingPathComponent("feed-flow-2", isDirectory: true)
    let nested = androidProject.appendingPathComponent("app/src/main", isDirectory: true)
    let sourceFile = nested.appendingPathComponent("version.properties")

    try fileManager.createDirectory(at: nested, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: workspaceRoot.appendingPathComponent(".git"), withIntermediateDirectories: true)
    try Data().write(to: androidProject.appendingPathComponent("settings.gradle.kts"))
    try Data().write(to: sourceFile)

    let normalized = PathHeuristics.normalizeProjectPath(from: sourceFile, fileManager: fileManager)
    #expect(normalized?.path == workspaceRoot.path)
}

@Test
func normalizeProjectPath_usesParentDirectoryForXcodeProjectBundles() throws {
    let fileManager = FileManager.default
    let base = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let iosApp = base.appendingPathComponent("iosApp", isDirectory: true)
    let xcodeproj = iosApp.appendingPathComponent("MoneyFlow.xcodeproj", isDirectory: true)
    let pbxproj = xcodeproj.appendingPathComponent("project.pbxproj")

    try fileManager.createDirectory(at: xcodeproj, withIntermediateDirectories: true)
    try Data().write(to: pbxproj)

    let normalizedFromBundle = PathHeuristics.normalizeProjectPath(from: xcodeproj, fileManager: fileManager)
    #expect(normalizedFromBundle?.path == iosApp.path)

    let normalizedFromProjectFile = PathHeuristics.normalizeProjectPath(from: pbxproj, fileManager: fileManager)
    #expect(normalizedFromProjectFile?.path == iosApp.path)
}

@Test
func normalizeProjectPath_findsVcsRootWhenNoNearerMarkersExist() throws {
    let fileManager = FileManager.default
    let base = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? fileManager.removeItem(at: base) }
    let workspaceRoot = base.appendingPathComponent("android-workspace", isDirectory: true)
    let moduleRoot = workspaceRoot.appendingPathComponent("feature/login", isDirectory: true)
    let sourceDir = moduleRoot.appendingPathComponent("src/main", isDirectory: true)
    let sourceFile = sourceDir.appendingPathComponent("MainActivity.kt")

    try fileManager.createDirectory(at: sourceDir, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: workspaceRoot.appendingPathComponent(".git"), withIntermediateDirectories: true)
    try Data().write(to: sourceFile)

    let normalized = PathHeuristics.normalizeProjectPath(from: sourceFile, fileManager: fileManager)
    #expect(normalized?.path == workspaceRoot.path)
}
