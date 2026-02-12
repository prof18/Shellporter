import Foundation

extension Bundle {
    /// Resource bundle that works both in development (swift build/run) and in the packaged .app.
    ///
    /// SwiftPM's auto-generated `Bundle.module` looks for the resource bundle next to
    /// `Bundle.main.bundleURL`, which is the `.app` root for packaged apps. Code signing
    /// forbids loose files at the `.app` root, so the resource bundle lives in
    /// `Contents/Resources/` instead. This accessor checks that location first.
    static let appResources: Bundle = {
        let bundleName = "Shellporter_Shellporter"

        // Packaged .app: Contents/Resources/<bundle>
        if let resourceURL = Bundle.main.resourceURL,
           let bundle = Bundle(url: resourceURL.appendingPathComponent("\(bundleName).bundle"))
        {
            return bundle
        }

        // Development (swift build): bundle sits next to the executable
        let mainPath = Bundle.main.bundleURL.appendingPathComponent("\(bundleName).bundle")
        if let bundle = Bundle(path: mainPath.path) {
            return bundle
        }

        fatalError("Could not load resource bundle \(bundleName)")
    }()
}
