import SwiftUI

struct AccessibilityOnboardingView: View {
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 40)

            appIcon

            Spacer()
                .frame(height: 20)

            title

            Spacer()
                .frame(height: 12)

            description

            Spacer()
                .frame(height: 32)

            buttons

            Spacer()
                .frame(height: 28)
        }
        .padding(.horizontal, 40)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var appIcon: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .frame(width: 96, height: 96)
    }

    private var title: some View {
        Text(AppStrings.Onboarding.title)
            .font(.system(size: 22, weight: .bold))
            .multilineTextAlignment(.center)
    }

    private var description: some View {
        Text(AppStrings.Onboarding.description)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            Button(action: onQuit) {
                Text(AppStrings.Onboarding.quit)
                    .frame(minWidth: 100)
            }
            .controlSize(.large)

            Button(action: onOpenSettings) {
                Text(AppStrings.Onboarding.openSystemSettings)
                    .frame(minWidth: 140)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}
