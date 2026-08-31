import AppKit
import SwiftUI

struct InspectorView: View {
    @Bindable var state: AppState

    var body: some View {
        Form {
            if let capture = state.capture {
                Section("Capture") {
                    LabeledContent("File", value: capture.url.lastPathComponent)
                    LabeledContent("Size", value: "\(Int(capture.pixelSize.width)) × \(Int(capture.pixelSize.height))")
                    if capture.kind == .video {
                        LabeledContent("Duration", value: capture.duration.formatted(.number.precision(.fractionLength(1))) + " s")
                        LabeledContent("Frame rate", value: capture.nominalFrameRate.formatted(.number.precision(.fractionLength(0...2))) + " fps")
                        LabeledContent("Audio", value: capture.hasAudio ? "Included" : "None")
                    }
                }
            }

            Section("Device Frame") {
                Picker("Device", selection: Binding(
                    get: { state.selectedDevice ?? "" },
                    set: { state.selectDevice($0) }
                )) {
                    ForEach(state.deviceNames, id: \.self) { Text($0).tag($0) }
                }

                Picker("Orientation", selection: Binding(
                    get: { state.selectedFrame?.orientation ?? .portrait },
                    set: { state.selectOrientation($0) }
                )) {
                    ForEach(FrameOrientation.allCases) { Text($0.title).tag($0) }
                }

                Picker("Variant", selection: Binding(
                    get: { state.selectedFrame?.variant ?? "" },
                    set: { state.selectVariant($0) }
                )) {
                    ForEach(state.availableVariants, id: \.self) { Text($0).tag($0) }
                }

                if state.detection?.isAmbiguous == true {
                    Label("Several devices share this resolution. Confirm the device above.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if state.cropWarning {
                    Label("This capture uses a different aspect ratio and will be center-cropped.", systemImage: "crop")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Canvas") {
                Picker("Layout", selection: Binding(
                    get: { state.settings.canvasPreset },
                    set: { state.setCanvasPreset($0) }
                )) {
                    ForEach(CanvasPreset.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                Picker("Background", selection: Binding(
                    get: { state.settings.background.mode },
                    set: { state.setBackgroundMode($0) }
                )) {
                    ForEach(BackgroundMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                if state.settings.background.mode == .solid {
                    ColorPicker("Color", selection: Binding(
                        get: { Color(nsColor: state.settings.background.color.nsColor) },
                        set: { state.setBackgroundColor(NSColor($0)) }
                    ), supportsOpacity: false)
                }
            }

            Section("Export") {
                Picker("Format", selection: Binding(
                    get: { state.settings.exportFormat },
                    set: { state.setExportFormat($0) }
                )) {
                    if state.capture?.kind == .video {
                        Text("MOV").tag(ExportFormat.mov)
                        Text("MP4").tag(ExportFormat.mp4)
                    } else {
                        Text("PNG").tag(ExportFormat.png)
                    }
                }
                .pickerStyle(.segmented)

                if state.settings.exportFormat == .mp4 && state.settings.background.mode == .transparent {
                    Label("MP4 requires a solid background.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if state.isExporting {
                    ProgressView(value: state.exportProgress)
                    Button("Cancel Export") { state.cancelExport() }
                } else {
                    Button("Export…") { state.export() }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                        .disabled(!state.canExport)
                    if state.capture?.kind == .image {
                        Button(state.isCopying ? "Preparing Copy…" : "Copy Image") { state.copyImage() }
                            .frame(maxWidth: .infinity)
                            .disabled(!state.canCopyImage)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}
