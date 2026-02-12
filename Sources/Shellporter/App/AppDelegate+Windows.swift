import AppKit
import SwiftUI

extension AppDelegate {
    func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        updateStatusBarIcon()
        rebuildMenu()
    }

    func updateStatusBarIcon() {
        guard let button = statusItem?.button else { return }
        if let image = statusBarImage(missingPermission: !accessibilityPermissionGranted) {
            button.image = image
            button.title = ""
        } else {
            button.image = nil
            button.title = AppStrings.StatusBar.fallbackTitle
        }

        if accessibilityPermissionGranted {
            button.toolTip = AppStrings.StatusBar.tooltipDefault
        } else {
            button.toolTip = AppStrings.StatusBar.tooltipAccessibilityMissing
        }
    }

    @objc
    func openAboutWindow() {
        if aboutWindowController == nil {
            let view = AboutView()
            let host = NSHostingController(rootView: view)

            let window = NSWindow(
                contentRect: NSRect(
                    x: 0,
                    y: 0,
                    width: aboutWindowSize.width,
                    height: aboutWindowSize.height
                ),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.contentViewController = host
            window.title = AppStrings.Window.aboutTitle
            window.minSize = NSSize(width: 560, height: 560)
            window.center()

            aboutWindowController = NSWindowController(window: window)
        }

        NSApp.activate(ignoringOtherApps: true)
        aboutWindowController?.showWindow(nil)
        aboutWindowController?.window?.makeKeyAndOrderFront(nil)
        // Center after SwiftUI has completed its layout pass.
        if let window = aboutWindowController?.window {
            DispatchQueue.main.async { [weak self] in
                self?.centerWindowOnVisibleScreen(window)
            }
        }
    }

    @objc
    func openPreferences() {
        if settingsWindowController == nil {
            let viewModel = SettingsViewModel(
                config: configStore.config,
                onConfigChange: { [weak self] updatedConfig in
                    guard let self else { return }
                    let previousConfig = configStore.config
                    configStore.update { current in
                        current = updatedConfig
                    }

                    if previousConfig.hotkeyKeyCode != updatedConfig.hotkeyKeyCode
                        || previousConfig.hotkeyModifiers != updatedConfig.hotkeyModifiers
                        || previousConfig.copyCommandHotkeyKeyCode != updatedConfig.copyCommandHotkeyKeyCode
                        || previousConfig.copyCommandHotkeyModifiers != updatedConfig.copyCommandHotkeyModifiers {
                        registerHotkeys()
                        rebuildMenu()
                    }
                    if previousConfig.defaultTerminal != updatedConfig.defaultTerminal {
                        rebuildMenu()
                    }
                },
                onCopyDiagnostics: { [weak self] in
                    _ = self?.copyLastResolutionDiagnosticsToPasteboard()
                },
                canCopyDiagnostics: { [weak self] in
                    self?.lastResolutionContext != nil
                }
            )
            let view = SettingsView(viewModel: viewModel)
            let host = NSHostingController(rootView: view)

            let window = NSWindow(
                contentRect: NSRect(
                    x: 0,
                    y: 0,
                    width: preferencesDefaultSize.width,
                    height: preferencesDefaultSize.height
                ),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.minSize = preferencesMinSize
            window.contentViewController = host
            window.title = AppStrings.Window.preferencesTitle
            window.center()

            settingsWindowController = NSWindowController(window: window)
        }

        NSApp.activate(ignoringOtherApps: true)
        enforceMinimumPreferencesWindowSize()
        settingsWindowController?.showWindow(nil)
    }

    func showAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    private func statusBarImage(missingPermission: Bool) -> NSImage? {
        if let customImage = loadCustomStatusBarImage() {
            return customImage
        }

        let symbolNames = missingPermission
            ? ["terminal.badge.exclamationmark", "terminal", "exclamationmark.triangle"]
            : ["terminal", "chevron.left.forwardslash.chevron.right"]

        for symbol in symbolNames {
            if let image = NSImage(
                systemSymbolName: symbol,
                accessibilityDescription: AppStrings.StatusBar.symbolAccessibilityDescription
            ) {
                image.isTemplate = true
                return image
            }
        }
        return nil
    }

    private func loadCustomStatusBarImage() -> NSImage? {
        let names = ["shellporter-menubar-normal-18", "shellporter-menubar-normal-36"]

        let image = NSImage(size: menuBarIconSize)
        var hasRepresentation = false

        for name in names {
            guard
                let url = Bundle.module.url(forResource: name, withExtension: "png")
                    ?? Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "MenuBarIcons"),
                let sourceImage = NSImage(contentsOf: url)
            else {
                continue
            }

            for representation in sourceImage.representations {
                guard let copy = representation.copy() as? NSImageRep else {
                    continue
                }
                copy.size = menuBarIconSize
                image.addRepresentation(copy)
                hasRepresentation = true
            }
        }

        guard hasRepresentation else { return nil }
        image.isTemplate = true
        return image
    }

    private func enforceMinimumPreferencesWindowSize() {
        guard let window = settingsWindowController?.window else { return }
        var frame = window.frame
        let width = max(frame.width, preferencesMinSize.width)
        let height = max(frame.height, preferencesMinSize.height)
        if width != frame.width || height != frame.height {
            frame.size = NSSize(width: width, height: height)
            window.setFrame(frame, display: true, animate: false)
        }
    }

    private func centerWindowOnVisibleScreen(_ window: NSWindow) {
        guard let screen = NSApp.mainWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first else {
            window.center()
            return
        }
        let visibleFrame = screen.visibleFrame
        let x = visibleFrame.midX - (window.frame.width / 2)
        let y = visibleFrame.midY - (window.frame.height / 2)
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
