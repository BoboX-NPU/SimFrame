import SwiftUI

@main
struct SimFrameApp: App {
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup {
            MainView(state: state)
                .frame(minWidth: 920, minHeight: 640)
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Capture…") { state.chooseCapture() }
                    .keyboardShortcut("o", modifiers: .command)
                Button("Import or Replace Frame Library…") { state.chooseFrameLibrary() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .saveItem) {
                Button("Export…") { state.export() }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(!state.canExport)
            }
            CommandGroup(after: .pasteboard) {
                Button("Copy Framed Image") { state.copyImage() }
                    .keyboardShortcut("c", modifiers: .command)
                    .disabled(state.capture?.kind != .image || state.previewImage == nil)
            }
#if DEBUG
            FrameInspectorCommands()
#endif
        }

#if DEBUG
        Window("Frame Inspector", id: "frame-inspector") {
            FrameInspectorView()
        }
        .defaultSize(width: 920, height: 680)
#endif
    }
}

#if DEBUG
private struct FrameInspectorCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("Developer") {
            Button("Frame Inspector…") { openWindow(id: "frame-inspector") }
                .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }
}
#endif

