import SwiftUI

struct OnboardingView: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(.tint)

            VStack(spacing: 8) {
                Text("Bring your own Apple device frames")
                    .font(.title2.weight(.semibold))
                Text("SimFrame keeps Apple artwork outside the app bundle. Download the official product bezels, then import the extracted PNG folder once.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }

            HStack(spacing: 12) {
                Button("Open Apple Design Resources") { state.openAppleResources() }
                Button("Import Frame Folder…") { state.chooseFrameLibrary() }
                    .buttonStyle(.borderedProminent)
            }

            Button("Review Apple Marketing Guidelines") { state.openMarketingGuidelines() }
                .buttonStyle(.link)
                .font(.caption)
        }
        .padding(48)
    }
}

