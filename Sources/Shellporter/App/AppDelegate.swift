import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let logger = Logger()
    lazy var configStore = ConfigStore(logger: logger)
    lazy var resolutionCacheStore = ResolutionCacheStore(logger: logger)
    lazy var resolver = FocusedProjectResolver(
        logger: logger,
        cacheStore: resolutionCacheStore
    )
    lazy var terminalLauncher = TerminalLauncher(logger: logger)
    let sparkleUpdater = SparkleUpdater()
    let openHotKeyManager = HotKeyManager(signature: "SHPO", id: 1)
    let copyCommandHotKeyManager = HotKeyManager(signature: "SHPC", id: 1)

    var statusItem: NSStatusItem?
    var settingsWindowController: NSWindowController?
    var aboutWindowController: NSWindowController?
    var onboardingWindowController: NSWindowController?
    var lastResolutionContext: ResolvedProjectContext?
    var accessibilityPermissionGranted = false
    var permissionMonitorTimer: Timer?
    /// Tracks the last non-Shellporter app the user was in. When the hotkey fires,
    /// Shellporter may already be frontmost (e.g. menu was open), so we need to
    /// remember which IDE to resolve against. Updated via workspace notifications.
    var lastKnownExternalApp: NSRunningApplication?
    let shellporterBundleIdentifier = Bundle.main.bundleIdentifier ?? "com.prof18.shellporter"
    let preferencesMinSize = NSSize(width: 720, height: 620)
    let preferencesDefaultSize = NSSize(width: 780, height: 700)
    let aboutWindowSize = NSSize(width: 600, height: 620)
    let onboardingSize = NSSize(width: 480, height: 380)
    let menuBarIconSize = NSSize(width: 18, height: 18)

    func applicationDidFinishLaunching(_ notification: Notification) {
        configStore.load()
        setupStatusItem()
        registerHotkeys()
        refreshAccessibilityPermissionStatus()

        // Track app activations so we know which IDE was last focused (see lastKnownExternalApp).
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWorkspaceAppActivation(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        rebuildMenu()
        maybeShowAccessibilityOnboarding()
        if !accessibilityPermissionGranted {
            startPermissionMonitor()
        }
        logger.log("Shellporter started")
    }

    func applicationWillTerminate(_ notification: Notification) {
        openHotKeyManager.unregister()
        copyCommandHotKeyManager.unregister()
        stopPermissionMonitor()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
