import Foundation

struct AppBuildInfo: Equatable {
    let bundleIdentifier: String
    let displayName: String

    var isDevBuild: Bool {
        bundleIdentifier.hasSuffix(".dev")
            || displayName.localizedCaseInsensitiveContains("dev")
    }

    static func current(bundle: Bundle = .main) -> AppBuildInfo {
        let bundleIdentifier = bundle.bundleIdentifier ?? "com.prof18.shellporter"
        let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Shellporter"
        return AppBuildInfo(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName
        )
    }
}
