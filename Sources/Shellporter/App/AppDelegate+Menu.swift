import AppKit

extension AppDelegate {
    func rebuildMenu() {
        guard let statusItem else { return }
        _ = refreshAccessibilityPermissionStatus()

        let menu = NSMenu()

        if buildInfo.isDevBuild {
            menu.addItem(makeDevBuildIndicatorItem())
            menu.addItem(.separator())
        }

        if !accessibilityPermissionGranted {
            let accessibilityStatus = NSMenuItem(
                title: AppStrings.Menu.accessibilityMissing,
                action: nil,
                keyEquivalent: ""
            )
            accessibilityStatus.isEnabled = false
            menu.addItem(accessibilityStatus)

            let requestPermission = NSMenuItem(
                title: AppStrings.Menu.requestAccessibilityPermission,
                action: #selector(requestAccessibilityPermission),
                keyEquivalent: ""
            )
            requestPermission.target = self
            menu.addItem(requestPermission)

            let openSettings = NSMenuItem(
                title: AppStrings.Menu.openAccessibilitySettings,
                action: #selector(openAccessibilitySettings),
                keyEquivalent: ""
            )
            openSettings.target = self
            menu.addItem(openSettings)
        }

        menu.addItem(.separator())

        let openItemKeyEquivalent = HotKeyShortcut.keyEquivalent(for: configStore.config.hotkeyKeyCode)
        let openItem = NSMenuItem(
            title: AppStrings.Menu.openTerminalInCurrentProject,
            action: #selector(openWithDefaultTerminal),
            keyEquivalent: openItemKeyEquivalent
        )
        openItem.target = self
        openItem.keyEquivalentModifierMask = HotKeyShortcut.modifierFlags(fromCarbonModifiers: configStore.config.hotkeyModifiers)
        menu.addItem(openItem)

        let copyItem = NSMenuItem(
            title: AppStrings.Menu.focusTerminalAndCopyCommand,
            action: #selector(copyCdCommandForCurrentProject),
            keyEquivalent: HotKeyShortcut.keyEquivalent(for: configStore.config.copyCommandHotkeyKeyCode)
        )
        copyItem.target = self
        copyItem.keyEquivalentModifierMask = HotKeyShortcut.modifierFlags(
            fromCarbonModifiers: configStore.config.copyCommandHotkeyModifiers
        )
        menu.addItem(copyItem)

        let openWithItem = NSMenuItem(title: AppStrings.Menu.openWith, action: nil, keyEquivalent: "")
        openWithItem.submenu = makeOpenWithMenu()
        menu.addItem(openWithItem)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: AppStrings.Menu.preferences, action: #selector(openPreferences), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let checkForUpdates = NSMenuItem(
            title: AppStrings.Menu.checkForUpdates,
            action: #selector(checkForUpdatesAction),
            keyEquivalent: ""
        )
        checkForUpdates.target = self
        menu.addItem(checkForUpdates)

        let about = NSMenuItem(title: AppStrings.Menu.aboutShellporter, action: #selector(openAboutWindow), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(title: AppStrings.Menu.quitShellporter, action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        menu.delegate = self
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        if refreshAccessibilityPermissionStatus() {
            rebuildMenu()
        }
    }

    private func makeOpenWithMenu() -> NSMenu {
        let submenu = NSMenu()
        for terminal in TerminalChoice.allCases {
            let item = NSMenuItem(
                title: terminal.displayName,
                action: #selector(openWithSelectedTerminal(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = terminal.rawValue
            submenu.addItem(item)
        }
        return submenu
    }

    private func makeDevBuildIndicatorItem() -> NSMenuItem {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 12),
            .foregroundColor: NSColor.systemOrange,
        ]
        let item = NSMenuItem(title: AppStrings.Menu.devBuildIndicator, action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(
            string: AppStrings.Menu.devBuildIndicator,
            attributes: attributes
        )
        item.isEnabled = false
        return item
    }

    @objc func checkForUpdatesAction() {
        sparkleUpdater.checkForUpdates()
    }

    @objc
    private func quitApp() {
        NSApp.terminate(nil)
    }
}
