# SimFrame Current State

Last updated: 2026-08-31

## Project Purpose

SimFrame is a local-first macOS utility that composites iOS Simulator screenshots or recordings into user-imported Apple product device frames. All assets and rendering are processed locally.

## Technical Baseline

- Platform: macOS 15.0+
- UI framework: SwiftUI
- Language: Swift 6
- Project: `SimFrame.xcodeproj`, with `SimFrame` as the primary scheme
- App version: 1.0 (build 1)
- Bundle identifier: `com.xuemingbo.SimFrame`
- Security: App Sandbox and Hardened Runtime are enabled
- Project collaboration documentation is maintained in English.
- Every completed project update refreshes `doc/current.md`, appends `doc/devlog.md`, and ends with a Git commit using a short English title. The body includes only the applicable `New Features`, `Improvements`, and `Bug Fixes` sections; empty sections and headings are omitted. Each `Bug Fixes` entry describes a fix actually completed in that change.

## Implemented Capabilities

- Imports a local directory of transparent PNG device frames on first launch. Frames are copied to Application Support, original Apple artwork is not stored in the repository, and the manifest remains at schema version 1.
- Scans the transparent screen opening in each PNG, generates a derived grayscale-alpha mask under `FrameLibrary/Masks`, and preserves the previous frames and masks if replacement fails. Existing libraries automatically rebuild missing, corrupt, or dimensionally invalid masks without requiring re-import.
- Opens Simulator screenshots or recordings in PNG, JPEG, HEIC, MOV, and MP4 formats.
- Automatically matches a device using pixel dimensions, aspect ratio, filename, and the previous selection, while allowing manual device, orientation, and appearance-variant selection.
- Provides Original, Balanced, and Spacious canvas presets with transparent or solid backgrounds.
- Previews, copies, and exports images as PNG. Mismatched aspect ratios use center cropping and display a warning. Image content is clipped only to the alpha-derived outer screen silhouette: horizontal and vertical span envelopes fill Dynamic Island, notch, and camera occlusions, while border-connected exterior transparency remains excluded and a two-pixel overlap keeps content beneath the bezel. Device-frame artwork is always the final top layer and visually covers those internal hardware regions.
- Renders still-image previews at the current viewport pixel size after a 150 ms resize debounce without upscaling beyond the source output. Full-resolution rendering remains in use for PNG export and clipboard copy.
- Exports videos as MOV or MP4 with progress reporting and cancellation, while preserving an available audio track. Video preview and export use the same precomputed, two-pixel-overlap screen mask as still images, and device-frame artwork remains the final top layer.
- Loads frame artwork and masks away from the main actor and retains the most recently used decoded assets in a deterministic 128 MB byte-cost LRU cache. Library replacement clears the cache, and a single frame metadata edit invalidates only that frame.
- Separates frame-loading, still-preview, clipboard-copy, and resize-debounce tasks. New frame and preview requests cancel older work and use request generations so stale results cannot replace the latest Picker selection.
- Previews video with a native `AVPlayerView` surface and the same precomputed outer-screen mask used by export. Playback controls are a separate responsive overlay sized from the full preview area rather than the device screen aperture, with a minimum width of 400 points and a maximum width of 1,000 points. The overlay provides enlarged 30-point play and mute button targets, seeking, elapsed and total time, and window-scoped Space-key play/pause that ignores automatic key repeats. Device-frame artwork remains non-interactive so the controls receive pointer input.
- Keeps the main workspace focused on the preview and optional recent captures without a persistent status footer.
- Keeps the top-right toolbar limited to opening a capture and selecting the device-frame library. Export remains available in the inspector without a duplicate toolbar action.
- Uses HEVC with Alpha for transparent MOV, HEVC for opaque MOV, and H.264 for MP4. Video export normalizes source orientation and calculates the target bitrate from source bitrate and output pixel area. The target never falls below the source bitrate and includes 10% VBR headroom when source bitrate metadata is available.
- Saves and restores recently opened capture files.
- Includes a device-frame inspector for correcting the screen region of imported frames.

## Project Structure

- `SimFrame/App`: Application entry point
- `SimFrame/Views`: Main interface, onboarding, preview, inspector, and recent-capture views
- `SimFrame/Stores`: Application state and user workflows
- `SimFrame/Services`: Frame library, capture inspection, image and video rendering, and recent-capture persistence
- `SimFrame/Support`: Composition geometry and logging
- `SimFrame/DeveloperTools`: Device-frame inspection tools
- `SimFrameTests`: Unit and media-export tests
- `SimFrameUITests`: Onboarding UI test
- `script`: Build, launch, and validation-fixture scripts
- `doc`: Current project state and development history

## Current Dependencies and Constraints

- The repository does not include Apple device-frame artwork. Users must obtain Apple Design Resources and import the extracted PNG directory themselves.
- MP4 does not support a transparent background and therefore requires a solid background.
- Video export re-encodes the source rather than remuxing it losslessly. The source-aware bitrate strategy prevents a lower target bitrate but cannot make a lossy codec byte-for-byte identical to the source.
- Some media tests require local fixtures generated by `script/generate_validation_fixtures.sh`. Those tests are skipped when the fixtures are unavailable.

## Current Validation Status

- The project contains 28 unit and media tests plus 1 UI test. Coverage includes frame scanning and atomic replacement, derived-mask creation and repair, decoded-asset reuse, Dynamic Island and connected-notch masking, rounded exterior transparency, two-pixel bezel overlap, viewport-sized preview rendering, full-resolution output, stale-request rejection, device matching, video orientation, codecs, audio, transparency, playback behavior, and target bitrate.
- Standard test command: `xcodebuild -project SimFrame.xcodeproj -scheme SimFrame -destination 'platform=macOS' test`
- On 2026-08-31, all 28 unit and media tests passed with 0 failures in 81.481 seconds. This run included the local 30-frame Apple library scan, the full-resolution iPhone 17 Pro Max PNG regression, and the local HEVC with Alpha audio fixture.
- On 2026-08-31, `./script/build_and_run.sh --verify` succeeded after the frame-loading and preview changes.
- A running-app inspection confirmed that all 30 masks were automatically created for the existing library; PNG and video previews preserved rounded exterior clipping while the top-layer device artwork covered Dynamic Island; rapid Device and Variant changes settled on the latest choice; window zoom and restore regenerated a ready preview; and full-resolution Copy became available after frame assets loaded.
- An eight-second rapid-switch sample showed no alpha flood-fill, mask generation, or full-resolution Core Image output on the main thread. Observed PNG decoding occurred on SwiftUI's background `prepare-image` queue.

## Outstanding Work

- No confirmed frame-switching, mask, preview, copy, or export blocker is currently known.
- The onboarding UI test launches an application process without a window under the current macOS 27/Xcode automation environment, so its three element assertions fail. The same built app creates its window and displays onboarding normally when launched by `build_and_run.sh`; this remains an automation-environment follow-up.
- The first launch of an existing 30-frame high-resolution library may remain on onboarding while missing masks are generated. In the current local library this one-time migration completed successfully and subsequent launches use the cached masks.
- Existing AVFoundation deprecation warnings remain in `VideoRenderer.swift`; they do not affect the completed validation results.
