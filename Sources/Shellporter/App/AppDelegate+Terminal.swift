import AppKit

extension AppDelegate {
    func registerHotkeys() {
        openHotKeyManager.register(
            keyCode: configStore.config.hotkeyKeyCode,
            modifiers: configStore.config.hotkeyModifiers
        ) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.resolveAndOpenTerminal(using: self.configStore.config.defaultTerminal)
            }
        }

        copyCommandHotKeyManager.register(
            keyCode: configStore.config.copyCommandHotkeyKeyCode,
            modifiers: configStore.config.copyCommandHotkeyModifiers
        ) { [weak self] in
            Task { @MainActor [weak self] in
                await self?.copyCdCommandForCurrentProjectAction()
            }
        }
    }

    @objc
    func openWithDefaultTerminal() {
        let terminal = configStore.config.defaultTerminal
        Task { @MainActor [weak self] in
            await self?.resolveAndOpenTerminal(using: terminal)
        }
    }

    @objc
    func openWithSelectedTerminal(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let terminal = TerminalChoice(rawValue: rawValue)
        else {
            return
        }
        Task { @MainActor [weak self] in
            await self?.resolveAndOpenTerminal(using: terminal)
        }
    }

    @objc
    func copyCdCommandForCurrentProject() {
        Task { @MainActor [weak self] in
            await self?.copyCdCommandForCurrentProjectAction()
        }
    }

    private func copyCdCommandForCurrentProjectAction() async {
        if !accessibilityPermissionGranted {
            showAccessibilityOnboarding()
            return
        }

        let context = await resolver.resolve(targetApp: preferredTargetApp())
        lastResolutionContext = context
        rebuildMenu()

        guard let projectPath = context.projectPath else {
            logger.log(
                "Resolver failed for \(context.appName) (\(context.bundleIdentifier)) while copying cd command: \(context.details)"
            )
            showAlert(
                title: AppStrings.Alerts.projectPathNotFoundTitle,
                message: AppStrings.Alerts.projectPathNotFoundMessage
            )
            return
        }

        let command = "cd \(projectPath.path.shellEscapedForBash())"
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(command, forType: .string)
        logger.log("Copied cd command to pasteboard: \(command)")

        _ = focusTerminalApp(choice: configStore.config.defaultTerminal)
    }

    @discardableResult
    func copyLastResolutionDiagnosticsToPasteboard() -> Bool {
        guard let context = lastResolutionContext else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(context.diagnosticsSummary, forType: .string)
        logger.log("Copied resolution diagnostics to pasteboard")
        return true
    }

    /// Every time any app activates, remember it (unless it's us). This is the fallback
    /// for `preferredTargetApp()` when Shellporter itself is frontmost at hotkey time.
    @objc
    func handleWorkspaceAppActivation(_ notification: Notification) {
        guard
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
            let bundleID = app.bundleIdentifier
        else {
            return
        }

        if bundleID != shellporterBundleIdentifier {
            lastKnownExternalApp = app
        }
    }

    @objc
    func handleAppDidBecomeActive() {
        if refreshAccessibilityPermissionStatus() {
            rebuildMenu()
        }
    }

    private func resolveAndOpenTerminal(using terminal: TerminalChoice) async {
        if !accessibilityPermissionGranted {
            showAccessibilityOnboarding()
            return
        }

        let context = await resolver.resolve(targetApp: preferredTargetApp())
        lastResolutionContext = context
        rebuildMenu()

        if let projectPath = context.projectPath {
            launchTerminal(at: projectPath, using: terminal)
            return
        }

        logger.log(
            "Resolver failed for \(context.appName) (\(context.bundleIdentifier)): \(context.details)"
        )
        openManualDirectoryPicker(using: terminal)
    }

    private func launchTerminal(at path: URL, using terminal: TerminalChoice) {
        do {
            try terminalLauncher.launch(at: path, choice: terminal, config: configStore.config)
        } catch {
            logger.log("Terminal launch failed: \(error.localizedDescription)")
            showAlert(
                title: AppStrings.Alerts.failedToLaunchTerminalTitle,
                message: error.localizedDescription
            )
        }
    }

    private func openManualDirectoryPicker(using terminal: TerminalChoice) {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.title = AppStrings.Alerts.selectProjectFolderTitle
        panel.message = AppStrings.Alerts.selectProjectFolderMessage
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = AppStrings.Alerts.openTerminalPrompt

        if panel.runModal() == .OK, let url = panel.url {
            launchTerminal(at: url, using: terminal)
        }
    }

    @discardableResult
    private func focusTerminalApp(choice: TerminalChoice) -> Bool {
        guard let bundleID = choice.bundleIdentifier else {
            logger.log("Skipping terminal focus for \(choice.displayName): no bundle identifier")
            return false
        }

        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first(where: { !$0.isTerminated }) {
            let activated = app.activate(options: [])
            logger.log("Focused running terminal \(choice.displayName); activated=\(activated)")
            return activated
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            logger.log("Terminal \(choice.displayName) could not be resolved from bundle identifier \(bundleID)")
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { app, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    self.logger.log("Failed to launch terminal \(choice.displayName): \(error.localizedDescription)")
                    return
                }
                self.logger.log("Terminal \(choice.displayName) launch requested; app=\(app?.localizedName ?? "unknown")")
            }
        }
        return true
    }

    /// Decides which app to resolve against. Usually the frontmost app, but when Shellporter
    /// is frontmost (e.g. user clicked the menu bar icon, or the hotkey raced with focus),
    /// we fall back to the last external app we tracked via workspace notifications.
    private func preferredTargetApp() -> NSRunningApplication? {
        if
            let frontmost = NSWorkspace.shared.frontmostApplication,
            let bundleID = frontmost.bundleIdentifier,
            bundleID != shellporterBundleIdentifier
        {
            return frontmost
        }

        if let cached = lastKnownExternalApp {
            if cached.isTerminated {
                lastKnownExternalApp = nil
            } else {
                return cached
            }
        }

        return NSWorkspace.shared.frontmostApplication
    }
}
