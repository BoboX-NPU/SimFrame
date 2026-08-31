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
        .inspector(isPresented: .constant(true)) {
            InspectorView(state: state)
                .inspectorColumnWidth(min: 260, ideal: 300, max: 360)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { state.chooseCapture() } label: {
                    Label("Open Capture", systemImage: "photo.on.rectangle")
                }
                .disabled(state.manifest == nil)

                Button { state.chooseFrameLibrary() } label: {
                    Label("Frame Library", systemImage: "iphone.gen3")
                }
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
