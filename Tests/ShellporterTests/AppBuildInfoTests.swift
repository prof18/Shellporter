import Testing
@testable import Shellporter

@Test
func appBuildInfo_detectsDevBundleIdentifier() {
    let info = AppBuildInfo(
        bundleIdentifier: "com.prof18.shellporter.dev",
        displayName: "Shellporter"
    )

    #expect(info.isDevBuild)
}

@Test
func appBuildInfo_detectsDevDisplayName() {
    let info = AppBuildInfo(
        bundleIdentifier: "com.prof18.shellporter",
        displayName: "Shellporter Dev"
    )

    #expect(info.isDevBuild)
}

@Test
func appBuildInfo_treatsReleaseAsNonDev() {
    let info = AppBuildInfo(
        bundleIdentifier: "com.prof18.shellporter",
        displayName: "Shellporter"
    )

    #expect(!info.isDevBuild)
}
