import AppKit
import Sparkle

@MainActor
final class SparkleUpdater: NSObject {
    private let controller: SPUStandardUpdaterController

    override init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
        controller.updater.automaticallyChecksForUpdates = true
        controller.startUpdater()
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// Whether Sparkle can currently perform an update check.
    /// Use this to enable/disable the "Check for Updates" menu item.
    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }
}
