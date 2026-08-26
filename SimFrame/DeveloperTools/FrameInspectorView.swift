#if DEBUG
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FrameInspectorView: View {
    @State private var frameURL: URL?
    @State private var frameImage: NSImage?
    @State private var sampleURL: URL?
    @State private var previewImage: NSImage?
    @State private var device = "iPhone"
    @State private var variant = "Black"
    @State private var orientation = FrameOrientation.portrait
    @State private var screenRect = CGRect.zero
    @State private var dragStart: CGPoint?
    @State private var errorMessage: String?

    var body: some View {
        HSplitView {
            canvas
                .frame(minWidth: 560)

            Form {
                Section("Frame") {
                    Button("Open Frame PNG…") { openFrame() }
                    TextField("Device", text: $device)
                    TextField("Variant", text: $variant)
                    Picker("Orientation", selection: $orientation) {
                        ForEach(FrameOrientation.allCases) { Text($0.title).tag($0) }
                    }
                }
                Section("Screen Rect") {
                    LabeledContent("X", value: Int(screenRect.minX).description)
                    LabeledContent("Y", value: Int(screenRect.minY).description)
                    LabeledContent("Width", value: Int(screenRect.width).description)
                    LabeledContent("Height", value: Int(screenRect.height).description)
                    Text("Drag across the display opening to replace the automatic rectangle.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Validate") {
                    Button("Open Sample Capture…") { openSample() }
                        .disabled(frameURL == nil)
                    Button("Preview Composition") { renderPreview() }
                        .disabled(frameURL == nil || sampleURL == nil || screenRect.isEmpty)
                    Button("Save Metadata JSON…") { saveJSON() }
                        .disabled(frameURL == nil || screenRect.isEmpty)
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 280, idealWidth: 320)
        }
        .alert("Frame Inspector", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    @ViewBuilder
    private var canvas: some View {
        GeometryReader { proxy in
            if let previewImage {
                Image(nsImage: previewImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let frameImage {
                let fit = fittedRect(imageSize: frameImage.size, container: proxy.size)
                ZStack(alignment: .topLeading) {
                    CheckerboardView()
                    Image(nsImage: frameImage)
                        .resizable()
                        .frame(width: fit.width, height: fit.height)
                        .position(x: fit.midX, y: fit.midY)
                    Rectangle()
                        .stroke(.red, lineWidth: 2)
                        .background(.red.opacity(0.08))
                        .frame(width: screenRect.width * fit.width / frameImage.size.width,
                               height: screenRect.height * fit.height / frameImage.size.height)
                        .position(
                            x: fit.minX + screenRect.midX * fit.width / frameImage.size.width,
                            y: fit.minY + screenRect.midY * fit.height / frameImage.size.height
                        )
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let start = dragStart ?? value.startLocation
                        dragStart = start
                        screenRect = imageRect(from: start, to: value.location, fit: fit, imageSize: frameImage.size)
                    }
                    .onEnded { _ in dragStart = nil })
            } else {
                ContentUnavailableView("Open a device frame", systemImage: "iphone.gen3", description: Text("The transparent screen opening will be detected automatically."))
            }
        }
        .padding(18)
    }

    private func openFrame() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png]
        guard panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) else { return }
        frameURL = url
        frameImage = image
        previewImage = nil
        do {
            let scanned = try FrameScanner.scan(url: url)
            device = scanned.device
            variant = scanned.variant
            orientation = scanned.orientation
            screenRect = scanned.screenRect
        } catch {
            screenRect = CGRect(x: image.size.width * 0.06, y: image.size.height * 0.04,
                                width: image.size.width * 0.88, height: image.size.height * 0.92)
            errorMessage = "Automatic detection failed. Mark the screen manually. \(error.localizedDescription)"
        }
    }

    private func openSample() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK else { return }
        sampleURL = panel.url
        previewImage = nil
    }

    private func renderPreview() {
        guard let frameURL, let frameImage, let sampleURL else { return }
        let frame = currentFrame(size: frameImage.size)
        do {
            previewImage = try ImageRenderer().preview(
                contentURL: sampleURL,
                frameURL: frameURL,
                frame: frame,
                settings: RenderSettings(frameID: frame.id)
            )
        } catch { errorMessage = error.localizedDescription }
    }

    private func saveJSON() {
        guard let frameURL, let frameImage else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(frameURL.deletingPathExtension().lastPathComponent).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(currentFrame(size: frameImage.size)).write(to: url, options: .atomic)
        } catch { errorMessage = error.localizedDescription }
    }

    private func currentFrame(size: CGSize) -> DeviceFrame {
        let normalized = CGRect(
            x: screenRect.minX / size.width, y: screenRect.minY / size.height,
            width: screenRect.width / size.width, height: screenRect.height / size.height
        )
        let id = [device, variant, orientation.rawValue].joined(separator: "-").lowercased()
            .replacingOccurrences(of: " ", with: "-")
        return DeviceFrame(id: id, device: device, variant: variant, orientation: orientation,
                           frameFile: frameURL?.lastPathComponent ?? "frame.png", canvasSize: size,
                           screenRect: screenRect, normalizedScreenRect: normalized,
                           expectedCaptureSizes: [screenRect.size])
    }

    private func fittedRect(imageSize: CGSize, container: CGSize) -> CGRect {
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (container.width - size.width) / 2, y: (container.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    private func imageRect(from start: CGPoint, to end: CGPoint, fit: CGRect, imageSize: CGSize) -> CGRect {
        let startX = min(max(start.x, fit.minX), fit.maxX)
        let startY = min(max(start.y, fit.minY), fit.maxY)
        let endX = min(max(end.x, fit.minX), fit.maxX)
        let endY = min(max(end.y, fit.minY), fit.maxY)
        let viewRect = CGRect(x: min(startX, endX), y: min(startY, endY),
                              width: abs(endX - startX), height: abs(endY - startY))
        return CGRect(
            x: (viewRect.minX - fit.minX) * imageSize.width / fit.width,
            y: (viewRect.minY - fit.minY) * imageSize.height / fit.height,
            width: viewRect.width * imageSize.width / fit.width,
            height: viewRect.height * imageSize.height / fit.height
        ).integral
    }
}
#endif

