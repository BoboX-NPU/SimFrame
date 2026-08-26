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
            Divider()
            statusBar
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

                Button { state.export() } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(!state.canExport)
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

    private var statusBar: some View {
        HStack(spacing: 10) {
            if state.isImportingFrames || state.isExporting {
                ProgressView(value: state.isExporting ? state.exportProgress : nil)
                    .controlSize(.small)
                    .frame(width: 96)
            }
            Text(state.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if let manifest = state.manifest {
                Text("\(manifest.frames.count) frames · \(manifest.displayName)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
    }
}

