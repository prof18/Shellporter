import Testing
@testable import Shellporter

@Test
func ideFamily_mapsJetBrainsAndAndroidStudioBundles() {
    let jetBrainsBundles = [
        "com.jetbrains.intellij",
        "com.jetbrains.intellij.ce",
        "com.jetbrains.pycharm",
        "com.jetbrains.pycharm.ce",
        "com.jetbrains.webstorm",
        "com.jetbrains.datagrip",
        "com.jetbrains.clion",
        "com.jetbrains.rider",
        "com.jetbrains.rubymine",
        "com.jetbrains.goland",
        "com.jetbrains.phpstorm",
        "com.jetbrains.dataspell",
        "com.jetbrains.rustrover",
        "com.jetbrains.fleet",
        "com.jetbrains.gateway",
        "com.intellij.idea",
        "org.jetbrains.intellij",
        "com.google.android.studio",
        "com.google.android.studio.preview",
        "com.google.android.studio.canary",
    ]

    for bundle in jetBrainsBundles {
        #expect(IDEFamily.from(bundleIdentifier: bundle) == .jetBrains)
    }
}

@Test
func ideFamily_mapsVSCodeBundles() {
    #expect(IDEFamily.from(bundleIdentifier: "com.microsoft.VSCode") == .vscode)
    #expect(IDEFamily.from(bundleIdentifier: "com.microsoft.VSCodeInsiders") == .vscode)
    #expect(IDEFamily.from(bundleIdentifier: "com.vscodium") == .vscode)
}

@Test
func ideFamily_mapsCursorBundles() {
    #expect(IDEFamily.from(bundleIdentifier: "com.todesktop.230313mzl4w4u92") == .cursor)
    #expect(IDEFamily.from(bundleIdentifier: "com.cursor.editor") == .cursor)
}

@Test
func ideFamily_mapsAntigravity() {
    #expect(IDEFamily.from(bundleIdentifier: "com.google.antigravity") == .antigravity)
}

@Test
func ideFamily_mapsXcode() {
    #expect(IDEFamily.from(bundleIdentifier: "com.apple.dt.Xcode") == .xcode)
}

@Test
func ideFamily_doesNotMapUnrelatedBundleToJetBrains() {
    #expect(IDEFamily.from(bundleIdentifier: "com.apple.finder") == .unknown)
}

@Test
func ideFamily_caseInsensitive() {
    #expect(IDEFamily.from(bundleIdentifier: "COM.MICROSOFT.VSCODE") == .vscode)
    #expect(IDEFamily.from(bundleIdentifier: "Com.Apple.Dt.Xcode") == .xcode)
    #expect(IDEFamily.from(bundleIdentifier: "COM.JETBRAINS.INTELLIJ") == .jetBrains)
}
