import Foundation
import Testing
@testable import Shellporter

@Test
func jetBrainsRecents_picksMatchingProjectNameFromWindowTitle() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? fileManager.removeItem(at: tempRoot) }
    let projectA = tempRoot.appendingPathComponent("feed-flow", isDirectory: true)
    let projectB = tempRoot.appendingPathComponent("reader-flow", isDirectory: true)
    let optionsDir = tempRoot
        .appendingPathComponent("JetBrains/IntelliJIdea2025.1/options", isDirectory: true)

    try fileManager.createDirectory(at: projectA, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: projectB, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: optionsDir, withIntermediateDirectories: true)

    let xml = """
    <application>
      <component name="RecentProjectsManager">
        <option name="additionalInfo">
          <map>
            <entry key="\(projectA.path)"/>
            <entry key="\(projectB.path)"/>
          </map>
        </option>
      </component>
    </application>
    """
    try xml.write(to: optionsDir.appendingPathComponent("recentProjects.xml"), atomically: true, encoding: .utf8)

    let resolved = JetBrainsRecentProjectsResolver.resolve(
        windowTitle: "reader-flow - Main.kt",
        fileManager: fileManager,
        searchRoots: [tempRoot.appendingPathComponent("JetBrains", isDirectory: true)]
    )

    #expect(resolved?.path == projectB.path)
}

@Test
func jetBrainsRecents_returnsNilWhenHintsMissingAndMultipleCandidatesExist() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? fileManager.removeItem(at: tempRoot) }
    let projectA = tempRoot.appendingPathComponent("feed-flow", isDirectory: true)
    let projectB = tempRoot.appendingPathComponent("reader-flow", isDirectory: true)
    let optionsDir = tempRoot
        .appendingPathComponent("JetBrains/AndroidStudio2025.1/options", isDirectory: true)

    try fileManager.createDirectory(at: projectA, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: projectB, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: optionsDir, withIntermediateDirectories: true)

    let xml = """
    <application>
      <component name="RecentProjectsManager">
        <option name="additionalInfo">
          <map>
            <entry key="\(projectA.path)"/>
            <entry key="\(projectB.path)"/>
          </map>
        </option>
      </component>
    </application>
    """
    try xml.write(to: optionsDir.appendingPathComponent("recentProjects.xml"), atomically: true, encoding: .utf8)

    let resolved = JetBrainsRecentProjectsResolver.resolve(
        windowTitle: nil,
        fileManager: fileManager,
        searchRoots: [tempRoot.appendingPathComponent("JetBrains", isDirectory: true)]
    )

    #expect(resolved == nil)
}

@Test
func jetBrainsRecents_returnsSingleCandidateWithoutHints() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? fileManager.removeItem(at: tempRoot) }
    let projectA = tempRoot.appendingPathComponent("feed-flow", isDirectory: true)
    let optionsDir = tempRoot
        .appendingPathComponent("JetBrains/AndroidStudio2025.1/options", isDirectory: true)

    try fileManager.createDirectory(at: projectA, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: optionsDir, withIntermediateDirectories: true)

    let xml = """
    <application>
      <component name="RecentProjectsManager">
        <option name="additionalInfo">
          <map>
            <entry key="\(projectA.path)"/>
          </map>
        </option>
      </component>
    </application>
    """
    try xml.write(to: optionsDir.appendingPathComponent("recentProjects.xml"), atomically: true, encoding: .utf8)

    let resolved = JetBrainsRecentProjectsResolver.resolve(
        windowTitle: nil,
        fileManager: fileManager,
        searchRoots: [tempRoot.appendingPathComponent("JetBrains", isDirectory: true)]
    )

    #expect(resolved?.path == projectA.path)
}

@Test
func jetBrainsRecents_prefersLatestAndroidStudioEntryForSimilarProjectNames() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? fileManager.removeItem(at: tempRoot) }
    let googleRoot = tempRoot.appendingPathComponent("Google", isDirectory: true)
    let oldOptions = googleRoot.appendingPathComponent("AndroidStudio2025.2/options", isDirectory: true)
    let newOptions = googleRoot.appendingPathComponent("AndroidStudio2025.3/options", isDirectory: true)

    let workspaceRoot = tempRoot.appendingPathComponent("feedflow", isDirectory: true)
    let projectRoot = workspaceRoot.appendingPathComponent("feed-flow", isDirectory: true)
    try fileManager.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: projectRoot, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: oldOptions, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: newOptions, withIntermediateDirectories: true)

    let oldXml = """
    <application>
      <component name="RecentProjectsManager">
        <option name="additionalInfo">
          <map>
            <entry key="\(workspaceRoot.path)">
              <value><RecentProjectMetaInfo frameTitle="FeedFlow – Old.kt [FeedFlow]"/></value>
            </entry>
          </map>
        </option>
      </component>
    </application>
    """
    let newXml = """
    <application>
      <component name="RecentProjectsManager">
        <option name="additionalInfo">
          <map>
            <entry key="\(projectRoot.path)">
              <value><RecentProjectMetaInfo frameTitle="FeedFlow – disable-android-for-flatpak.sh [FeedFlow]"/></value>
            </entry>
          </map>
        </option>
        <option name="lastOpenedProject" value="\(projectRoot.path)" />
      </component>
    </application>
    """

    let oldFile = oldOptions.appendingPathComponent("recentProjects.xml")
    let newFile = newOptions.appendingPathComponent("recentProjects.xml")
    try oldXml.write(to: oldFile, atomically: true, encoding: .utf8)
    try newXml.write(to: newFile, atomically: true, encoding: .utf8)

    try fileManager.setAttributes(
        [.modificationDate: Date(timeIntervalSince1970: 100)],
        ofItemAtPath: oldFile.path
    )
    try fileManager.setAttributes(
        [.modificationDate: Date(timeIntervalSince1970: 200)],
        ofItemAtPath: newFile.path
    )

    let resolved = JetBrainsRecentProjectsResolver.resolve(
        windowTitle: "FeedFlow – flatpak-build-setup.sh [FeedFlow]",
        fileManager: fileManager,
        searchRoots: [googleRoot]
    )

    #expect(resolved?.path == projectRoot.path)
}

@Test
func jetBrainsRecents_prefersExactFolderNameOverFrameTitleWithExplicitPath() throws {
    // Window title "FeedFlow – ..." suggests feed-flow; feed-flow-2 has frame with path in metadata.
    // We prefer exact name match (feed-flow) over sibling whose stored frame has path (feed-flow-2).
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? fileManager.removeItem(at: tempRoot) }
    let googleRoot = tempRoot.appendingPathComponent("Google", isDirectory: true)
    let options = googleRoot.appendingPathComponent("AndroidStudio2025.3/options", isDirectory: true)
    let feedFlow = tempRoot.appendingPathComponent("feedflow/feed-flow", isDirectory: true)
    let feedFlow2 = tempRoot.appendingPathComponent("feedflow/feed-flow-2", isDirectory: true)

    try fileManager.createDirectory(at: feedFlow, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: feedFlow2, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: options, withIntermediateDirectories: true)

    let xml = """
    <application>
      <component name="RecentProjectsManager">
        <option name="additionalInfo">
          <map>
            <entry key="\(feedFlow2.path)">
              <value>
                <RecentProjectMetaInfo frameTitle="FeedFlow [\(feedFlow2.path)] – FeedItemParser.kt [FeedFlow.shared.androidMain]">
                  <option name="activationTimestamp" value="200" />
                  <option name="projectOpenTimestamp" value="200" />
                </RecentProjectMetaInfo>
              </value>
            </entry>
            <entry key="\(feedFlow.path)">
              <value>
                <RecentProjectMetaInfo frameTitle="FeedFlow – disable-android-for-flatpak.sh [FeedFlow]">
                  <option name="activationTimestamp" value="201" />
                  <option name="projectOpenTimestamp" value="201" />
                </RecentProjectMetaInfo>
              </value>
            </entry>
          </map>
        </option>
        <option name="lastOpenedProject" value="\(feedFlow.path)" />
      </component>
    </application>
    """
    try xml.write(
        to: options.appendingPathComponent("recentProjects.xml"),
        atomically: true,
        encoding: .utf8
    )

    let resolved = JetBrainsRecentProjectsResolver.resolve(
        windowTitle: "FeedFlow – flatpak-build-setup.sh [FeedFlow]",
        fileManager: fileManager,
        searchRoots: [googleRoot]
    )

    #expect(resolved?.path == feedFlow.path)
}

@Test
func jetBrainsRecents_prefersExactFolderNameOverSuffixedSibling() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? fileManager.removeItem(at: tempRoot) }
    let options = tempRoot
        .appendingPathComponent("JetBrains/IntelliJIdea2025.1/options", isDirectory: true)
    let core = tempRoot.appendingPathComponent("Workspace/Acme/acme-core", isDirectory: true)
    let core2 = tempRoot.appendingPathComponent("Workspace/Acme/acme-core-2", isDirectory: true)

    try fileManager.createDirectory(at: core, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: core2, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: options, withIntermediateDirectories: true)

    let xml = """
    <application>
      <component name="RecentProjectsManager">
        <option name="additionalInfo">
          <map>
            <entry key="\(core2.path)">
              <value>
                <RecentProjectMetaInfo frameTitle="AcmeCore – App.kt [acme-core-2]">
                  <option name="activationTimestamp" value="300" />
                  <option name="projectOpenTimestamp" value="300" />
                </RecentProjectMetaInfo>
              </value>
            </entry>
            <entry key="\(core.path)">
              <value>
                <RecentProjectMetaInfo frameTitle="AcmeCore – App.kt [acme-core]">
                  <option name="activationTimestamp" value="100" />
                  <option name="projectOpenTimestamp" value="100" />
                </RecentProjectMetaInfo>
              </value>
            </entry>
          </map>
        </option>
        <option name="lastOpenedProject" value="\(core2.path)" />
      </component>
    </application>
    """
    try xml.write(
        to: options.appendingPathComponent("recentProjects.xml"),
        atomically: true,
        encoding: .utf8
    )

    let resolved = JetBrainsRecentProjectsResolver.resolve(
        windowTitle: "acme-core - README.md",
        fileManager: fileManager,
        searchRoots: [tempRoot.appendingPathComponent("JetBrains", isDirectory: true)]
    )

    #expect(resolved?.path == core.path)
}

@Test
func jetBrainsRecents_returnsNilWhenHintsAreAmbiguousEvenIfLastOpenedExists() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? fileManager.removeItem(at: tempRoot) }
    let options = tempRoot
        .appendingPathComponent("JetBrains/IntelliJIdea2025.1/options", isDirectory: true)
    let alpha = tempRoot.appendingPathComponent("Workspace/Acme/alpha-core", isDirectory: true)
    let beta = tempRoot.appendingPathComponent("Workspace/Acme/beta-core", isDirectory: true)

    try fileManager.createDirectory(at: alpha, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: beta, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: options, withIntermediateDirectories: true)

    let xml = """
    <application>
      <component name="RecentProjectsManager">
        <option name="additionalInfo">
          <map>
            <entry key="\(alpha.path)"/>
            <entry key="\(beta.path)"/>
          </map>
        </option>
        <option name="lastOpenedProject" value="\(beta.path)" />
      </component>
    </application>
    """
    try xml.write(
        to: options.appendingPathComponent("recentProjects.xml"),
        atomically: true,
        encoding: .utf8
    )

    let resolved = JetBrainsRecentProjectsResolver.resolve(
        windowTitle: "README.md",
        fileManager: fileManager,
        searchRoots: [tempRoot.appendingPathComponent("JetBrains", isDirectory: true)]
    )

    #expect(resolved == nil)
}

@Test @MainActor
func resolutionCache_prefersTitleSpecificHit_thenBundleFallback() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? fileManager.removeItem(at: tempRoot) }
    let cacheURL = tempRoot.appendingPathComponent("resolution-cache.json")
    let pathA = tempRoot.appendingPathComponent("project-a", isDirectory: true)
    let pathB = tempRoot.appendingPathComponent("project-b", isDirectory: true)
    try fileManager.createDirectory(at: pathA, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: pathB, withIntermediateDirectories: true)

    let store = ResolutionCacheStore(logger: Logger(), fileManager: fileManager, cacheURL: cacheURL)
    store.record(bundleIdentifier: "com.test.ide", windowTitle: "Project A", path: pathA)
    store.record(bundleIdentifier: "com.test.ide", windowTitle: nil, path: pathB)

    let exact = store.lookup(bundleIdentifier: "com.test.ide", windowTitle: "Project A")
    let fallback = store.lookup(bundleIdentifier: "com.test.ide", windowTitle: "Unknown")

    #expect(exact?.path == pathA.path)
    #expect(fallback?.path == pathB.path)
}

@Test @MainActor
func resolutionCache_prunesStaleEntriesOnLoad() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? fileManager.removeItem(at: tempRoot) }
    let cacheURL = tempRoot.appendingPathComponent("resolution-cache.json")
    let existingPath = tempRoot.appendingPathComponent("alive-project", isDirectory: true)
    let deletedPath = tempRoot.appendingPathComponent("deleted-project", isDirectory: true)
    try fileManager.createDirectory(at: existingPath, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: deletedPath, withIntermediateDirectories: true)

    // Seed a cache with two entries
    let store = ResolutionCacheStore(logger: Logger(), fileManager: fileManager, cacheURL: cacheURL)
    store.record(bundleIdentifier: "com.test.ide", windowTitle: "Alive", path: existingPath)
    store.record(bundleIdentifier: "com.test.ide2", windowTitle: "Deleted", path: deletedPath)

    // Delete one project directory
    try fileManager.removeItem(at: deletedPath)

    // Reload: stale entry should be pruned
    let reloaded = ResolutionCacheStore(logger: Logger(), fileManager: fileManager, cacheURL: cacheURL)

    let alive = reloaded.lookup(bundleIdentifier: "com.test.ide", windowTitle: "Alive")
    let deleted = reloaded.lookup(bundleIdentifier: "com.test.ide2", windowTitle: "Deleted")

    #expect(alive?.path == existingPath.path)
    #expect(deleted == nil)
    // The stale entries should have been removed from the cache entirely, not just skipped on lookup.
    // entryCount should only include the surviving entries (1 exact + 1 last for com.test.ide = 2).
    #expect(reloaded.entryCount == 2)
}

@Test @MainActor
func resolutionCache_evictsOldestEntriesWhenOverCap() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? fileManager.removeItem(at: tempRoot) }
    let cacheURL = tempRoot.appendingPathComponent("resolution-cache.json")

    // Create more directories than the cap allows entries.
    // Each record() with a title produces 2 entries (exact + last), but the `last` key is shared
    // per bundle ID. So using distinct bundle IDs: each produces 2 entries.
    // We need > maxEntries total. With distinct bundles each producing 2 entries,
    // we need ceil(maxEntries / 2) + 1 bundles to exceed the cap.
    let bundleCount = (ResolutionCacheStore.maxEntries / 2) + 5

    for i in 0..<bundleCount {
        let dir = tempRoot.appendingPathComponent("project-\(i)", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    let store = ResolutionCacheStore(logger: Logger(), fileManager: fileManager, cacheURL: cacheURL)

    for i in 0..<bundleCount {
        let dir = tempRoot.appendingPathComponent("project-\(i)", isDirectory: true)
        store.record(
            bundleIdentifier: "com.test.ide\(i)",
            windowTitle: "Window \(i)",
            path: dir
        )
    }

    #expect(store.entryCount <= ResolutionCacheStore.maxEntries)
}

@Test @MainActor
func resolutionCache_migratesLegacyFormat() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? fileManager.removeItem(at: tempRoot) }
    let cacheURL = tempRoot.appendingPathComponent("resolution-cache.json")
    let projectPath = tempRoot.appendingPathComponent("my-project", isDirectory: true)
    try fileManager.createDirectory(at: projectPath, withIntermediateDirectories: true)

    // Write a legacy [String: String] cache file (the old format)
    let legacyCache: [String: String] = [
        "com.test.ide|title|my project": projectPath.path,
        "com.test.ide|last": projectPath.path,
    ]
    try fileManager.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try JSONEncoder().encode(legacyCache)
    try data.write(to: cacheURL, options: .atomic)

    // Loading should transparently migrate
    let store = ResolutionCacheStore(logger: Logger(), fileManager: fileManager, cacheURL: cacheURL)

    let result = store.lookup(bundleIdentifier: "com.test.ide", windowTitle: "My Project")
    #expect(result?.path == projectPath.path)
    #expect(store.entryCount == 2)
}

@Test @MainActor
func resolutionCache_evictionPreservesRecentEntries() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? fileManager.removeItem(at: tempRoot) }
    let cacheURL = tempRoot.appendingPathComponent("resolution-cache.json")

    let bundleCount = (ResolutionCacheStore.maxEntries / 2) + 5

    for i in 0..<bundleCount {
        let dir = tempRoot.appendingPathComponent("project-\(i)", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    let store = ResolutionCacheStore(logger: Logger(), fileManager: fileManager, cacheURL: cacheURL)

    // Record old entries first, then the "recent" one last
    for i in 0..<bundleCount {
        let dir = tempRoot.appendingPathComponent("project-\(i)", isDirectory: true)
        store.record(
            bundleIdentifier: "com.test.ide\(i)",
            windowTitle: "Window \(i)",
            path: dir
        )
    }

    // The most recently recorded entry should survive eviction
    let lastIndex = bundleCount - 1
    let recent = store.lookup(
        bundleIdentifier: "com.test.ide\(lastIndex)",
        windowTitle: "Window \(lastIndex)"
    )
    #expect(recent != nil)

    // The oldest entry should have been evicted
    let oldest = store.lookup(bundleIdentifier: "com.test.ide0", windowTitle: "Window 0")
    #expect(oldest == nil)
}

@Test
func editorRecents_resolvesCursorWorkspaceFromStorageJson() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? fileManager.removeItem(at: tempRoot) }
    let projectPath = tempRoot.appendingPathComponent("shellporter", isDirectory: true)
    let storageRoot = tempRoot.appendingPathComponent("Cursor/User/globalStorage", isDirectory: true)
    try fileManager.createDirectory(at: projectPath, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: storageRoot, withIntermediateDirectories: true)

    let json = """
    {
      "history.recentlyOpenedPathsList": {
        "entries": [
          {"folderUri": "file://\(projectPath.path)"}
        ]
      }
    }
    """
    try json.write(
        to: storageRoot.appendingPathComponent("storage.json"),
        atomically: true,
        encoding: .utf8
    )

    let resolved = EditorRecentsResolver.resolve(
        ideFamily: .cursor,
        windowTitle: "shellporter - Cursor",
        fileManager: fileManager,
        searchRoots: [storageRoot]
    )

    #expect(resolved?.path == projectPath.path)
}

@Test
func editorRecents_prefersMostRecentStorageWhenHintsAreMissing() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? fileManager.removeItem(at: tempRoot) }

    let oldProject = tempRoot.appendingPathComponent("old-project", isDirectory: true)
    let newProject = tempRoot.appendingPathComponent("new-project", isDirectory: true)
    let oldStorageRoot = tempRoot.appendingPathComponent("Code/User/globalStorage-old", isDirectory: true)
    let newStorageRoot = tempRoot.appendingPathComponent("Code/User/globalStorage-new", isDirectory: true)
    let oldStorageFile = oldStorageRoot.appendingPathComponent("storage.json")
    let newStorageFile = newStorageRoot.appendingPathComponent("storage.json")

    try fileManager.createDirectory(at: oldProject, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: newProject, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: oldStorageRoot, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: newStorageRoot, withIntermediateDirectories: true)

    let oldJSON = """
    {
      "history.recentlyOpenedPathsList": {
        "entries": [
          {"folderUri": "file://\(oldProject.path)"}
        ]
      }
    }
    """
    let newJSON = """
    {
      "history.recentlyOpenedPathsList": {
        "entries": [
          {"folderUri": "file://\(newProject.path)"}
        ]
      }
    }
    """

    try oldJSON.write(to: oldStorageFile, atomically: true, encoding: .utf8)
    try newJSON.write(to: newStorageFile, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: oldStorageFile.path)
    try fileManager.setAttributes([.modificationDate: Date(timeIntervalSince1970: 200)], ofItemAtPath: newStorageFile.path)

    let resolved = EditorRecentsResolver.resolve(
        ideFamily: .vscode,
        windowTitle: nil,
        fileManager: fileManager,
        searchRoots: [oldStorageRoot, newStorageRoot]
    )

    #expect(resolved?.path == newProject.path)
}
