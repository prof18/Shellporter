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
    @State private var availableTerminalChoices = SystemTerminalDetector.availableTerminalChoices()
    @State private var recordingTarget: ShortcutRecordingTarget?
    @State private var hotkeyCaptureMonitor: Any?
    @State private var hotkeyCaptureMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !accessibilityGranted {
                    accessibilityCallout
                }

                generalSection
                terminalSection
                shortcutsSection
                accessibilitySection
                if presentation.showsDiagnostics {
                    diagnosticsSection
                }
            }
            .frame(maxWidth: 680, alignment: .top)
            .padding(.horizontal, 28)
            .padding(.vertical, 26)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 640, minHeight: 600)
        .onAppear {
            refreshAccessibilityStatus()
            refreshAvailableTerminalChoices()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAvailableTerminalChoices()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            refreshAvailableTerminalChoices()
        }
        .onDisappear {
            stopHotkeyCapture()
            viewModel.flushPendingChanges()
        }
    }

    private var accessibilityCallout: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 6) {
                Text(AppStrings.Settings.accessibilityMissingCalloutTitle)
                    .font(.headline)
                Text(AppStrings.Settings.accessibilityMissingCalloutMessage)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button {
                        openAccessibilitySettings()
                    } label: {
                        Label(AppStrings.Settings.accessibilityOpenSettings, systemImage: "gearshape")
                    }

                    Button {
                        refreshAccessibilityStatus()
                    } label: {
                        Label(AppStrings.Settings.accessibilityRefreshStatus, systemImage: "arrow.clockwise")
                    }
                }
                .controlSize(.small)
                .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
        }
    }

    private var generalSection: some View {
        SettingsSection(AppStrings.Settings.sectionGeneral) {
            SettingsRow(title: AppStrings.Settings.launchAtLogin) {
                Toggle("", isOn: $launchAtLogin)
                    .labelsHidden()
                    .onChange(of: launchAtLogin) { _, newValue in
                        updateLaunchAtLogin(newValue)
                    }
            }
        }
    }

    private var terminalSection: some View {
        SettingsSection(AppStrings.Settings.sectionTerminal) {
            SettingsRow(title: AppStrings.Settings.fieldTerminal) {
                Picker("", selection: $viewModel.config.defaultTerminal) {
                    ForEach(availableTerminalChoices) { terminal in
                        Text(terminal.displayName).tag(terminal)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 190)
            }

            if presentation.showsGhosttyNewWindowOption {
                SettingsDivider()
                SettingsRow(
                    title: AppStrings.Settings.ghosttyOpenNewWindow,
                    subtitle: AppStrings.Settings.ghosttyOpenNewWindowHint
                ) {
                    Toggle("", isOn: $viewModel.config.ghosttyOpenNewWindow)
                        .labelsHidden()
                }
            }

            if presentation.showsCustomCommandEditor {
                SettingsDivider()
                customCommandEditor
            }
        }
    }

    private var customCommandEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppStrings.Settings.sectionCustomTerminalCommand)
                .font(.body)
                .foregroundStyle(.primary)

            Text(AppStrings.Settings.customCommandDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(AppStrings.Settings.fieldTemplate)
                    .foregroundStyle(.secondary)
                    .frame(width: 92, alignment: .leading)

                TextField(AppStrings.Settings.fieldTemplate, text: $viewModel.config.customCommandTemplate)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }

            Text(AppStrings.Settings.customCommandHint)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !presentation.customCommandHasPathPlaceholder {
                Text(AppStrings.Settings.customCommandMissingPathWarning)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var shortcutsSection: some View {
        SettingsSection(AppStrings.Settings.sectionGlobalShortcuts) {
            ShortcutPreferenceRow(
                title: AppStrings.Settings.openTerminalShortcut,
                shortcut: currentOpenShortcutDisplay,
                isRecording: recordingTarget == .openTerminal,
                isBlocked: recordingTarget != nil && recordingTarget != .openTerminal,
                onRecord: { startHotkeyCapture(for: .openTerminal) },
                onCancel: { stopHotkeyCapture() },
                onReset: {
                    stopHotkeyCapture()
                    viewModel.resetHotkeyToDefault()
                    hotkeyCaptureMessage = nil
                }
            )

            SettingsDivider()

            ShortcutPreferenceRow(
                title: AppStrings.Settings.focusTerminalCopyShortcut,
                subtitle: AppStrings.Settings.focusTerminalCopyHint,
                shortcut: currentCopyCommandShortcutDisplay,
                isRecording: recordingTarget == .copyCdCommand,
                isBlocked: recordingTarget != nil && recordingTarget != .copyCdCommand,
                onRecord: { startHotkeyCapture(for: .copyCdCommand) },
                onCancel: { stopHotkeyCapture() },
                onReset: {
                    stopHotkeyCapture()
                    viewModel.resetCopyCommandHotkeyToDefault()
                    hotkeyCaptureMessage = nil
                }
            )

            if let hotkeyCaptureMessage {
                SettingsDivider()
                InlineMessage(text: hotkeyCaptureMessage, style: .warning)
            } else if recordingTarget != nil {
                SettingsDivider()
                InlineMessage(text: AppStrings.Settings.hotkeyCaptureHint, style: .info)
            }
        }
    }

    private var accessibilitySection: some View {
        SettingsSection(AppStrings.Settings.sectionAccessibility) {
            SettingsRow(title: AppStrings.Settings.accessibilityStatus) {
                StatusPill(
                    text: accessibilityGranted
                        ? AppStrings.Settings.accessibilityGranted
                        : AppStrings.Settings.accessibilityMissing,
                    style: accessibilityGranted ? .success : .warning
                )
            }

            SettingsDivider()

            HStack(spacing: 8) {
                Button {
                    openAccessibilitySettings()
                } label: {
                    Label(AppStrings.Settings.accessibilityOpenSettings, systemImage: "gearshape")
                }

                Button {
                    refreshAccessibilityStatus()
                } label: {
                    Label(AppStrings.Settings.accessibilityRefreshStatus, systemImage: "arrow.clockwise")
                }

                Spacer(minLength: 0)
            }
            .controlSize(.small)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            SettingsDivider()

            HelpText(AppStrings.Settings.accessibilityHint)
        }
    }

    private var diagnosticsSection: some View {
        SettingsSection(AppStrings.Settings.sectionDiagnostics) {
            HStack(spacing: 8) {
                Button {
                    viewModel.copyLastResolutionDiagnostics()
                } label: {
                    Label(AppStrings.Settings.copyLastResolutionDiagnostics, systemImage: "doc.on.doc")
                }

                Spacer(minLength: 0)
            }
            .controlSize(.small)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            SettingsDivider()

            HelpText(AppStrings.Settings.diagnosticsHint)
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

    private var presentation: SettingsPresentation {
        SettingsPresentation(
            config: viewModel.config,
            canCopyDiagnostics: viewModel.canCopyLastResolutionDiagnostics
        )
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func refreshAccessibilityStatus() {
        accessibilityGranted = AXWindowInspector.isAccessibilityTrusted()
    }

    private func refreshAvailableTerminalChoices() {
        let choices = SystemTerminalDetector.availableTerminalChoices()
        availableTerminalChoices = choices
        guard !choices.contains(viewModel.config.defaultTerminal),
              let fallback = choices.first else {
            return
        }
        viewModel.config.defaultTerminal = fallback
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
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .padding(.leading, 2)

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
            }
        }
    }
}

private struct SettingsRow<Accessory: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let accessory: Accessory

    init(title: String, subtitle: String? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 16)

            accessory
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct ShortcutPreferenceRow: View {
    let title: String
    var subtitle: String?
    let shortcut: String
    let isRecording: Bool
    let isBlocked: Bool
    let onRecord: () -> Void
    let onCancel: () -> Void
    let onReset: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 8) {
                ShortcutCapsule(text: isRecording ? AppStrings.Settings.pressShortcut : shortcut, isRecording: isRecording)

                HStack(spacing: 6) {
                    if isRecording {
                        Button {
                            onCancel()
                        } label: {
                            Label(AppStrings.Settings.cancel, systemImage: "xmark")
                        }
                    }

                    Button {
                        onRecord()
                    } label: {
                        Label(AppStrings.Settings.recordShortcut, systemImage: "keyboard")
                    }
                    .disabled(isBlocked)

                    Button {
                        onReset()
                    } label: {
                        Label(AppStrings.Settings.resetDefault, systemImage: "arrow.counterclockwise")
                    }
                    .disabled(isBlocked)
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct ShortcutCapsule: View {
    let text: String
    let isRecording: Bool

    var body: some View {
        Text(text)
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(isRecording ? .orange : .secondary)
            .lineLimit(1)
            .textSelection(.enabled)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                isRecording ? Color.orange.opacity(0.12) : Color(nsColor: .quaternaryLabelColor).opacity(0.18),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
    }
}

private struct StatusPill: View {
    enum Style {
        case accent
        case success
        case warning

        var color: Color {
            switch self {
            case .accent:
                return .accentColor
            case .success:
                return .green
            case .warning:
                return .orange
            }
        }
    }

    let text: String
    let style: Style

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(style.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(style.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct InlineMessage: View {
    enum Style {
        case info
        case warning

        var color: Color {
            switch self {
            case .info:
                return .secondary
            case .warning:
                return .orange
            }
        }
    }

    let text: String
    let style: Style

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(style.color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HelpText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 14)
    }
}
