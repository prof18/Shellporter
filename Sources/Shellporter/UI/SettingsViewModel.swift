import Combine
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var config: AppConfig {
        didSet {
            configSubject.send(config)
        }
    }

    private let onConfigChange: (AppConfig) -> Void
    private let onCopyDiagnostics: () -> Void
    private let canCopyDiagnostics: () -> Bool
    private let configSubject = PassthroughSubject<AppConfig, Never>()
    private var cancellable: AnyCancellable?
    private var lastDeliveredConfig: AppConfig

    init(
        config: AppConfig,
        onConfigChange: @escaping (AppConfig) -> Void,
        onCopyDiagnostics: @escaping () -> Void = {},
        canCopyDiagnostics: @escaping () -> Bool = { false },
        debounceInterval: RunLoop.SchedulerTimeType.Stride = .milliseconds(300)
    ) {
        self.config = config
        self.onConfigChange = onConfigChange
        self.onCopyDiagnostics = onCopyDiagnostics
        self.canCopyDiagnostics = canCopyDiagnostics
        self.lastDeliveredConfig = config

        cancellable = configSubject
            .debounce(for: debounceInterval, scheduler: RunLoop.main)
            .sink { [weak self] updatedConfig in
                self?.lastDeliveredConfig = updatedConfig
                self?.onConfigChange(updatedConfig)
            }
    }

    var canCopyLastResolutionDiagnostics: Bool {
        canCopyDiagnostics()
    }

    func copyLastResolutionDiagnostics() {
        onCopyDiagnostics()
    }

    func flushPendingChanges() {
        guard config != lastDeliveredConfig else { return }
        lastDeliveredConfig = config
        onConfigChange(config)
    }

    func updateHotkey(keyCode: UInt32, modifiers: UInt32) {
        guard config.hotkeyKeyCode != keyCode || config.hotkeyModifiers != modifiers else {
            return
        }
        config.hotkeyKeyCode = keyCode
        config.hotkeyModifiers = modifiers
    }

    func resetHotkeyToDefault() {
        updateHotkey(
            keyCode: AppConfig.defaultHotkeyKeyCode,
            modifiers: AppConfig.defaultHotkeyModifiers
        )
    }

    func updateCopyCommandHotkey(keyCode: UInt32, modifiers: UInt32) {
        guard config.copyCommandHotkeyKeyCode != keyCode || config.copyCommandHotkeyModifiers != modifiers else {
            return
        }
        config.copyCommandHotkeyKeyCode = keyCode
        config.copyCommandHotkeyModifiers = modifiers
    }

    func resetCopyCommandHotkeyToDefault() {
        updateCopyCommandHotkey(
            keyCode: AppConfig.defaultCopyCommandHotkeyKeyCode,
            modifiers: AppConfig.defaultCopyCommandHotkeyModifiers
        )
    }

}
