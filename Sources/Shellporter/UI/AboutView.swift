import AppKit
import SwiftUI

struct AboutView: View {
    private struct SocialLink: Identifiable {
        let id: String
        let title: String
        let systemImage: String
        let url: URL
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 96, height: 96)

                Text(appName)
                    .font(.system(size: 36, weight: .bold))

                Text(versionLine)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(AppStrings.About.description)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 560)
                    .padding(.top, 4)

                VStack(spacing: 14) {
                    ForEach(socialLinks) { link in
                        Link(destination: link.url) {
                            Label(link.title, systemImage: link.systemImage)
                                .font(.title2.weight(.semibold))
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.vertical, 36)
        }
        .frame(minWidth: 560, minHeight: 560)
    }

    private var socialLinks: [SocialLink] {
        [
            makeLink(
                id: "github",
                title: AppStrings.About.github,
                systemImage: "chevron.left.forwardslash.chevron.right",
                rawURL: AppStrings.About.githubURL
            ),
            makeLink(
                id: "website",
                title: AppStrings.About.website,
                systemImage: "globe",
                rawURL: AppStrings.About.websiteURL
            ),
            makeLink(
                id: "twitter",
                title: AppStrings.About.twitter,
                systemImage: "bubble.left.and.bubble.right",
                rawURL: AppStrings.About.twitterURL
            ),
        ]
        .compactMap { $0 }
    }

    private func makeLink(id: String, title: String, systemImage: String, rawURL: String) -> SocialLink? {
        guard let url = URL(string: rawURL), !rawURL.isEmpty else {
            return nil
        }
        return SocialLink(id: id, title: title, systemImage: systemImage, url: url)
    }

    private var appName: String {
        if
            let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
            !displayName.isEmpty
        {
            return displayName
        }
        if
            let bundleName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String,
            !bundleName.isEmpty
        {
            return bundleName
        }
        return "Shellporter"
    }

    private var versionLine: String {
        String(format: AppStrings.About.versionFormat, shortVersion, buildNumber)
    }

    private var shortVersion: String {
        let defaultVersion = "0.1.0"
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            !value.isEmpty
        else {
            return defaultVersion
        }
        return value
    }

    private var buildNumber: String {
        let defaultBuild = "1"
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
            !value.isEmpty
        else {
            return defaultBuild
        }
        return value
    }

}
