import AppKit
import SwiftUI

extension AppDelegate {
    @objc
    func requestAccessibilityPermission() {
        let granted = AXWindowInspector.requestAccessibilityPrompt()
        logger.log("Requested accessibility permission prompt; granted=\(granted)")
        _ = refreshAccessibilityPermissionStatus()
        rebuildMenu()

        if !granted {
            startPermissionMonitor()
            openAccessibilitySettings()
        }
    }

    @objc
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @discardableResult
    func refreshAccessibilityPermissionStatus() -> Bool {
        let current = AXWindowInspector.isAccessibilityTrusted()
        let changed = current != accessibilityPermissionGranted
        accessibilityPermissionGranted = current
        updateStatusBarIcon()
        if current {
            stopPermissionMonitor()
            closeAccessibilityOnboardingWindow()
        } else {
            startPermissionMonitor()
        }
        return changed
    }

    func startPermissionMonitor() {
        guard permissionMonitorTimer == nil else { return }
        permissionMonitorTimer = Timer.scheduledTimer(
            withTimeInterval: 1.5,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if refreshAccessibilityPermissionStatus() {
                    rebuildMenu()
                }
            }
        }
        if let permissionMonitorTimer {
            RunLoop.main.add(permissionMonitorTimer, forMode: .common)
        }
    }

    func stopPermissionMonitor() {
        permissionMonitorTimer?.invalidate()
        permissionMonitorTimer = nil
    }

    func maybeShowAccessibilityOnboarding() {
        guard !accessibilityPermissionGranted else { return }
        showAccessibilityOnboarding()
    }

    func showAccessibilityOnboarding() {
        if let existingController = onboardingWindowController {
            NSApp.activate(ignoringOtherApps: true)
            existingController.showWindow(nil)
            existingController.window?.makeKeyAndOrderFront(nil)
            return
        }

        let onboardingView = AccessibilityOnboardingView(
            onOpenSettings: { [weak self] in
                self?.openAccessibilitySettings()
            },
            onQuit: {
                NSApp.terminate(nil)
            }
        )
        let host = NSHostingController(rootView: onboardingView)

        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: onboardingSize.width,
                height: onboardingSize.height
            ),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.contentViewController = host
        window.title = AppStrings.Window.onboardingTitle

        onboardingWindowController = NSWindowController(window: window)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindowController?.showWindow(nil)
        // Center after SwiftUI has completed its layout pass.
        DispatchQueue.main.async {
            window.center()
        }
    }

    private func closeAccessibilityOnboardingWindow() {
        onboardingWindowController?.close()
        onboardingWindowController = nil
    }
}
