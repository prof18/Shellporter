import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    private enum ShortcutRecordingTarget: String {
        case openTerminal
        case copyCdCommand
    }

    @ObservedObject var viewModel: SettingsViewModel
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var accessibilityGranted = AXWindowInspector.isAccessibilityTrusted()
    @State private var recordingTarget: ShortcutRecordingTarget?
    @State private var hotkeyCaptureMonitor: Any?
    @State private var hotkeyCaptureMessage: String?

    var body: some View {
        Form {
            Section(AppStrings.Settings.sectionGeneral) {
                Toggle(AppStrings.Settings.launchAtLogin, isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }

            Section(AppStrings.Settings.sectionDefaultTerminal) {
                Picker(AppStrings.Settings.fieldTerminal, selection: $viewModel.config.defaultTerminal) {
                    ForEach(TerminalChoice.allCases) { terminal in
                        Text(terminal.displayName).tag(terminal)
                    }
                }
                .pickerStyle(.menu)

                if viewModel.config.defaultTerminal == .ghostty {
                    Toggle(AppStrings.Settings.ghosttyOpenNewWindow, isOn: $viewModel.config.ghosttyOpenNewWindow)
                    Text(AppStrings.Settings.ghosttyOpenNewWindowHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(AppStrings.Settings.sectionCustomTerminalCommand) {
                Text(AppStrings.Settings.customCommandDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(AppStrings.Settings.fieldTemplate, text: $viewModel.config.customCommandTemplate)
                    .textFieldStyle(.roundedBorder)
                Text(AppStrings.Settings.customCommandHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !viewModel.config.customCommandTemplate.isEmpty
                    && !viewModel.config.customCommandTemplate.contains("{path}") {
                    Text(AppStrings.Settings.customCommandMissingPathWarning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section(AppStrings.Settings.sectionGlobalShortcuts) {
                if let hotkeyCaptureMessage {
                    Text(hotkeyCaptureMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text(AppStrings.Settings.hotkeyCaptureHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text(AppStrings.Settings.openTerminalShortcut)
                    Spacer()
                    Text(currentOpenShortcutDisplay)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                HStack {
                    Button(recordButtonTitle(for: .openTerminal)) {
                        startHotkeyCapture(for: .openTerminal)
                    }
                    .disabled(recordingTarget != nil && recordingTarget != .openTerminal)

                    Button(AppStrings.Settings.cancel) {
                        stopHotkeyCapture()
                    }
                    .disabled(recordingTarget != .openTerminal)

                    Button(AppStrings.Settings.resetDefault) {
                        stopHotkeyCapture()
                        viewModel.resetHotkeyToDefault()
                        hotkeyCaptureMessage = nil
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppStrings.Settings.focusTerminalCopyShortcut)
                        Text(AppStrings.Settings.focusTerminalCopyHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(currentCopyCommandShortcutDisplay)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                HStack {
                    Button(recordButtonTitle(for: .copyCdCommand)) {
                        startHotkeyCapture(for: .copyCdCommand)
                    }
                    .disabled(recordingTarget != nil && recordingTarget != .copyCdCommand)

                    Button(AppStrings.Settings.cancel) {
                        stopHotkeyCapture()
                    }
                    .disabled(recordingTarget != .copyCdCommand)

                    Button(AppStrings.Settings.resetDefault) {
                        stopHotkeyCapture()
                        viewModel.resetCopyCommandHotkeyToDefault()
                        hotkeyCaptureMessage = nil
                    }
                }
            }

            Section(AppStrings.Settings.sectionAccessibility) {
                HStack {
                    Text(AppStrings.Settings.accessibilityStatus)
                    Spacer()
                    Text(accessibilityGranted ? AppStrings.Settings.accessibilityGranted : AppStrings.Settings.accessibilityMissing)
                        .foregroundStyle(accessibilityGranted ? .green : .orange)
                }

                HStack {
                    Button(AppStrings.Settings.accessibilityOpenSettings) {
                        openAccessibilitySettings()
                    }

                    Button(AppStrings.Settings.accessibilityRefreshStatus) {
                        refreshAccessibilityStatus()
                    }
                }

                Text(AppStrings.Settings.accessibilityHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(AppStrings.Settings.sectionDiagnostics) {
                Button(AppStrings.Settings.copyLastResolutionDiagnostics) {
                    viewModel.copyLastResolutionDiagnostics()
                }
                .disabled(!viewModel.canCopyLastResolutionDiagnostics)
                Text(AppStrings.Settings.diagnosticsHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(16)
        .frame(minWidth: 720, minHeight: 620)
        .onAppear {
            refreshAccessibilityStatus()
        }
        .onDisappear {
            stopHotkeyCapture()
            viewModel.flushPendingChanges()
        }
    }

    private var currentOpenShortcutDisplay: String {
        HotKeyShortcut.displayString(
            keyCode: viewModel.config.hotkeyKeyCode,
            modifiers: viewModel.config.hotkeyModifiers
        )
    }

    private var currentCopyCommandShortcutDisplay: String {
        HotKeyShortcut.displayString(
            keyCode: viewModel.config.copyCommandHotkeyKeyCode,
            modifiers: viewModel.config.copyCommandHotkeyModifiers
        )
    }

    private func refreshAccessibilityStatus() {
        accessibilityGranted = AXWindowInspector.isAccessibilityTrusted()
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func startHotkeyCapture(for target: ShortcutRecordingTarget) {
        stopHotkeyCapture()
        recordingTarget = target
        hotkeyCaptureMessage = nil

        hotkeyCaptureMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handleCapturedHotkey(event)
            return nil
        }
    }

    private func stopHotkeyCapture() {
        if let hotkeyCaptureMonitor {
            NSEvent.removeMonitor(hotkeyCaptureMonitor)
            self.hotkeyCaptureMonitor = nil
        }
        recordingTarget = nil
    }

    private func handleCapturedHotkey(_ event: NSEvent) {
        // Escape cancels recording without changing the shortcut.
        if event.keyCode == 53 {
            stopHotkeyCapture()
            hotkeyCaptureMessage = nil
            return
        }

        let relevantFlags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let modifiers = HotKeyShortcut.carbonModifiers(fromEventFlags: relevantFlags)
        if modifiers == 0 {
            NSSound.beep()
            hotkeyCaptureMessage = AppStrings.Settings.hotkeyErrorModifierRequired
            return
        }

        let keyCode = UInt32(event.keyCode)
        guard HotKeyShortcut.isSupportedKeyCode(keyCode) else {
            NSSound.beep()
            hotkeyCaptureMessage = AppStrings.Settings.hotkeyErrorUnsupportedKey
            return
        }

        guard let recordingTarget else {
            stopHotkeyCapture()
            return
        }

        switch recordingTarget {
        case .openTerminal:
            viewModel.updateHotkey(keyCode: keyCode, modifiers: modifiers)
        case .copyCdCommand:
            viewModel.updateCopyCommandHotkey(keyCode: keyCode, modifiers: modifiers)
        }

        hotkeyCaptureMessage = nil
        stopHotkeyCapture()
    }

    private func recordButtonTitle(for target: ShortcutRecordingTarget) -> String {
        recordingTarget == target ? AppStrings.Settings.pressShortcut : AppStrings.Settings.recordShortcut
    }
}
