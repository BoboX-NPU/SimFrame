# SimFrame

English | [简体中文](README.zh-CN.md)

SimFrame is a fully local macOS app that turns iOS Simulator screenshots and recordings into polished device-framed visuals.

Import your own Apple product bezels, drop in a capture, adjust the frame and canvas, then export a presentation-ready image or video. The device-frame library, source media, previews, and rendered files all stay on your Mac.

## Highlights

- Processes everything locally without uploading media or frame artwork.
- Accepts PNG, JPEG, HEIC, MOV, and MP4 Simulator captures.
- Detects the likely device and orientation from dimensions, aspect ratio, filename, and the previous selection.
- Lets you manually choose the device, portrait or landscape orientation, and artwork variant.
- Offers Original, Balanced, and Spacious canvas layouts with transparent or custom solid backgrounds.
- Exports still images as PNG and videos as MOV or MP4, with progress and cancellation.
- Preserves an available audio track during video export.
- Uses each frame's alpha channel to derive the screen shape, keeping rounded corners clean and device hardware above the content.
- Remembers recent captures and includes an inspector for correcting imported frame metadata.

## Requirements

- macOS 15.0 or later
- Xcode with the macOS 15 SDK and Swift 6 support to build from source
- Transparent PNG device bezels from [Apple Design Resources](https://developer.apple.com/design/resources/)

Apple device artwork is not bundled with SimFrame or stored in this repository. Review [Apple's marketing guidelines](https://developer.apple.com/app-store/marketing/guidelines/) before distributing visuals that use Apple product images.

## Getting Started

1. Clone the repository:

   ```bash
   git clone https://github.com/BoboX-NPU/SimFrame.git
   cd SimFrame
   ```

2. Build and launch the app:

   ```bash
   ./script/build_and_run.sh
   ```

   You can also open `SimFrame.xcodeproj` in Xcode and run the `SimFrame` scheme.

3. Download the required product bezels from Apple Design Resources, extract the archive, and choose the folder that contains the transparent PNG files when SimFrame first opens.

4. Drop a Simulator screenshot or recording into the window, or use **Open Capture**.

5. Confirm the detected device frame, choose a canvas and background, then export from the inspector.

The imported frame library is copied to the app's Application Support directory. Replacing a library is atomic: cancelling or failing an import leaves the existing library available.

## Media and Export Support

| Source | Accepted formats | Export formats | Notes |
| --- | --- | --- | --- |
| Image | PNG, JPEG, HEIC | PNG | Supports transparent or solid backgrounds and clipboard copy. |
| Video | MOV, MP4 | MOV, MP4 | MOV supports transparent or solid backgrounds. MP4 requires a solid background. |

Transparent MOV export uses HEVC with Alpha. Opaque MOV uses HEVC, while MP4 uses H.264. Video export re-encodes the source and uses a source-aware bitrate target; it is not a lossless remux.

If the capture and selected frame have different aspect ratios, SimFrame center-crops the capture and shows a warning before export.

## Development

The project is a native SwiftUI macOS app with no third-party runtime dependencies.

```text
SimFrame/App             Application entry point
SimFrame/Views           Main interface, preview, onboarding, and inspector
SimFrame/Stores          Application state and user workflows
SimFrame/Services        Frame import, media inspection, and rendering
SimFrame/Support         Composition geometry and logging
SimFrame/DeveloperTools  Device-frame inspection tools
SimFrameTests            Unit and media-export tests
SimFrameUITests          Onboarding UI test
script                   Build and validation-fixture scripts
doc                      Current project state and development history
```

Build and run:

```bash
./script/build_and_run.sh
```

Run the test suite:

```bash
xcodebuild -project SimFrame.xcodeproj -scheme SimFrame -destination 'platform=macOS' test
```

Generate optional local media fixtures (requires `ffmpeg`):

```bash
./script/generate_validation_fixtures.sh
```

Generated fixtures and imported Apple artwork are ignored by Git. Some media tests skip automatically when their local fixtures are unavailable.

For the latest implementation status, validation record, and known limitations, see [doc/current.md](doc/current.md). Development history is recorded in [doc/devlog.md](doc/devlog.md).

