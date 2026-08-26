import SwiftUI

struct RecentCapturesView: View {
    @Bindable var state: AppState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("Recent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(state.recentCaptures) { record in
                    Button { state.openRecent(record) } label: {
                        Label(
                            record.displayName,
                            systemImage: record.kind == .image ? "photo" : "film"
                        )
                        .lineLimit(1)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(height: 46)
    }
}

