import SwiftUI

struct MainView: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if state.manifest == nil {
                    OnboardingView(state: state)
                } else {
                    DropPreviewView(state: state)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !state.recentCaptures.isEmpty {
                Divider()
                RecentCapturesView(state: state)
            }
        }
        .disabled(state.isImportingFrames)
        .inspector(isPresented: .constant(true)) {
            InspectorView(state: state)
                .inspectorColumnWidth(min: 260, ideal: 300, max: 360)
                .disabled(state.isImportingFrames)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { state.chooseCapture() } label: {
                    Label("Open Capture", systemImage: "photo.on.rectangle")
                }
                .disabled(state.manifest == nil || state.isImportingFrames)

                Button { state.chooseFrameLibrary() } label: {
                    Label("Frame Library", systemImage: "iphone.gen3")
                }
                .disabled(state.isImportingFrames)
            }
        }
        .overlay {
            if let phase = state.frameImportPhase {
                FrameImportOverlay(
                    phase: phase,
                    cancel: state.cancelFrameImport
                )
            }
        }
        .alert("SimFrame", isPresented: Binding(
            get: { state.errorMessage != nil },
            set: { if !$0 { state.clearError() } }
        )) {
            Button("OK") { state.clearError() }
        } message: {
            Text(state.errorMessage ?? "")
        }
    }

}

private struct FrameImportOverlay: View {
    let phase: FrameImportPhase
    let cancel: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "iphone.gen3")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.tint)

                VStack(spacing: 6) {
                    Text("Importing Device Frames")
                        .font(.headline)
                    Text(phase.detailText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Group {
                    if let fraction = phase.fractionCompleted {
                        ProgressView(value: fraction, total: 1)
                    } else {
                        ProgressView()
                    }
                }
                .progressViewStyle(.linear)
                .frame(width: 280)
                .accessibilityIdentifier("frameImportProgress")

                Button(phase == .cancelling ? "Cancelling…" : "Cancel Import", action: cancel)
                    .disabled(!phase.isCancellable)
                    .accessibilityIdentifier("cancelFrameImport")
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 26)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.quaternary)
            }
            .shadow(radius: 18, y: 8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("frameImportOverlay")
    }
}
