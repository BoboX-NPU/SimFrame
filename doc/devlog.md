# SimFrame Development Log

Append project changes to this file in chronological order. See `current.md` for the currently valid project state.

## 2026-08-26 — Established Current-State and Development-Log Documentation

### Change Summary

- Added project-level collaboration guidelines requiring every project update to refresh the current state and append to the development log.
- Added a current-state document covering the technical baseline, implemented capabilities, structure, dependencies, constraints, and validation status.
- Added an append-only development log as the single location for future change history.

### Affected Files

- `agents.md`
- `doc/current.md`
- `doc/devlog.md`

### Validation Results

- Compared `current.md` with `README.md`, the Xcode project configuration, core model and service code, and existing test files.
- Confirmed the paths and maintenance rules for all three documents.
- Application code was unchanged. Build and tests were not run.

### Risks or Follow-up Work

- None.

## 2026-08-26 — Standardized the Collaboration Filename and Documentation Language

### Change Summary

- Renamed the root-level `agents.md` file to the canonical `AGENTS.md` filename.
- Specified that `AGENTS.md`, `doc/current.md`, and `doc/devlog.md` were to be maintained in Chinese.
- Converted ordinary English section labels in the current-state document to Chinese while retaining filenames, code identifiers, commands, and technical terms in their original form to avoid ambiguity.

### Affected Files

- `AGENTS.md`
- `doc/current.md`
- `doc/devlog.md`

### Validation Results

- Checked the headings and body text in all three documents and confirmed that their explanatory content was written in Chinese.
- Confirmed that `AGENTS.md` existed at the project root and that lowercase `agents.md` was no longer present.
- Application code was unchanged. Build and tests were not run.

### Risks or Follow-up Work

- None.

## 2026-08-26 — Switched Project Documentation to English

### Change Summary

- Translated `AGENTS.md`, `doc/current.md`, and the existing `doc/devlog.md` history into English.
- Changed the project documentation policy so future collaboration documentation is maintained in English.
- Preserved the meaning and chronological order of the two existing development-log entries.

### Affected Files

- `AGENTS.md`
- `doc/current.md`
- `doc/devlog.md`

### Validation Results

- Checked all three documents for remaining Chinese characters.
- Confirmed that the root collaboration file remains named `AGENTS.md` and no lowercase `agents.md` exists.
- Application code was unchanged. Build and tests were not run.

### Risks or Follow-up Work

- None.

## 2026-08-26 — Added the Git Commit Workflow

### Change Summary

- Required every completed project update to end with a Git commit after documentation and validation are complete.
- Added a commit-message format with a short English title and the required New Features, Improvements, and Bug Fixes sections.
- Required staged files and commit claims to match the completed change.

### Affected Files

- `AGENTS.md`
- `doc/current.md`
- `doc/devlog.md`

### Validation Results

- Reviewed the Git workflow instructions and commit-message template in `AGENTS.md`.
- Confirmed that `current.md` records the active Git workflow and that this entry was appended to `devlog.md`.
- Application code was unchanged. Build and tests were not run.

### Risks or Follow-up Work

- The initial commit establishes the complete current project baseline.

## 2026-08-26 — Removed the Generic Bug-Fix Claim

### Change Summary

- Removed `Various bug fixes and performance improvements` from the Git commit template.
- Specified that a commit section remains empty when no corresponding change applies.

### Affected Files

- `AGENTS.md`
- `doc/current.md`
- `doc/devlog.md`

### Validation Results

- Confirmed that the generic bug-fix line is no longer present in the working project documentation.
- Application code was unchanged. Build and tests were not run.

### Risks or Follow-up Work

- None.

## 2026-08-26 — Required Evidence-Based Bug-Fix Entries

### Change Summary

- Required every Bug Fixes entry to describe a bug actually fixed in the current change.
- Added a specific placeholder to the template while preserving the rule that the section remains empty when no bug was fixed.
- Prohibited generic fallback claims in the Bug Fixes section.

### Affected Files

- `AGENTS.md`
- `doc/current.md`
- `doc/devlog.md`

### Validation Results

- Reviewed the commit-message instructions and confirmed that Bug Fixes entries are tied to actual completed fixes.
- Application code was unchanged. Build and tests were not run.

### Risks or Follow-up Work

- None.

## 2026-08-26 — Restored Video Preview Control Interaction

### Change Summary

- Diagnosed the visible but unresponsive video controls as a SwiftUI hit-testing conflict caused by device-frame artwork layered above the native `AVPlayerView`.
- Marked the device-frame artwork and preview border as non-interactive so pointer events reach the native playback controls.
- Kept the AppKit bridge limited to `StableVideoPlayer`; SwiftUI remains responsible for preview composition and player ownership.

### Affected Files

- `SimFrame/Views/DropPreviewView.swift`
- `doc/current.md`
- `doc/devlog.md`

### Validation Results

- Ran `xcodebuild -project SimFrame.xcodeproj -scheme SimFrame -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData test -only-testing:SimFrameTests/VideoRendererTests/testStableVideoPlayerCanBeHostedWithoutAVKitSwiftUIBridge`.
- Result: 1 test executed with 0 failures; the app and test targets compiled successfully and the native `AVPlayerView` bridge was hosted without failure.

### Risks or Follow-up Work

- End-to-end pointer interaction with a user-imported frame and recording remains a manual UI check.

## 2026-08-26 — Omitted Empty Commit-Message Sections

### Change Summary

- Changed the Git commit format so `New Features`, `Improvements`, and `Bug Fixes` headings appear only when they contain at least one completed item.
- Removed the previous requirement to retain empty sections in every commit body.
- Kept the evidence requirement for every included `Bug Fixes` entry.

### Affected Files

- `AGENTS.md`
- `doc/current.md`
- `doc/devlog.md`

### Validation Results

- Reviewed the Git commit instructions and confirmed that they explicitly require empty headings to be omitted.
- Application build and tests were not run because application code was unchanged.

### Risks or Follow-up Work

- Existing commit messages are unchanged; the new format applies to this and future commits.

## 2026-08-26 — Added Rounded Screen Clipping and Sharper MOV Output

### Change Summary

- Derived a reusable screen-aperture mask from each frame PNG's alpha channel so image and video content follows the frame's real rounded corners and display cutouts.
- Shared the same prepared frame artwork and aperture geometry across still-image and per-frame video composition.
- Raised the MOV bitrate floor and source-rate headroom to preserve fine device-frame highlights and antialiased edges more clearly than the MP4 policy.
- Added regression coverage for rounded alpha apertures and the higher-detail MOV bitrate policy.

### Affected Files

- `SimFrame/Services/ImageRenderer.swift`
- `SimFrame/Services/VideoRenderer.swift`
- `SimFrameTests/ImageRendererTests.swift`
- `SimFrameTests/TestImageFactory.swift`
- `SimFrameTests/VideoRendererTests.swift`
- `doc/current.md`
- `doc/devlog.md`

### Validation Results

- Ran 10 focused image and video regression tests with `xcodebuild`; all 10 passed with 0 failures.
- Passing coverage included rounded aperture masking, PNG output, MP4 H.264 export, video orientation, native-player hosting, and MOV/MP4 target-bitrate calculations.
- Started the local iPhone 17 Pro HEVC with Alpha MOV test twice, but intentionally interrupted both runs after impractically long encoding times. This test is not recorded as passing.
- The app and test targets compiled successfully. Existing AVFoundation deprecation warnings remain.

### Risks or Follow-up Work

- The user should visually inspect a representative transparent MOV export because the local high-resolution HEVC with Alpha integration test did not complete in a practical test time.
- Higher MOV quality can increase output size and encoding duration.

## 2026-08-26 — Corrected Rounded Clipping and Restored Source Bitrate Policy

### Change Summary

- Corrected the screen mask to carry the inverse frame alpha in its alpha channel and composited captures with `CIBlendWithAlphaMask`.
- Applied the same frame-derived rounded mask to the native video preview, which previously remained rectangular even though export composition had a mask.
- Generated and retained the selected frame's preview mask when the device frame changes.
- Removed the previous MOV-specific bitrate increase and restored the source-quality-density policy for all video formats: at least the source bitrate with 10% VBR headroom when source metadata is available.
- Replaced the mask-only test with a final-composition pixel test and added explicit coverage that the target video bitrate never drops below the source rate.

### Affected Files

- `SimFrame/Services/ImageRenderer.swift`
- `SimFrame/Services/VideoRenderer.swift`
- `SimFrame/Stores/AppState.swift`
- `SimFrame/Views/DropPreviewView.swift`
- `SimFrameTests/ImageRendererTests.swift`
- `SimFrameTests/VideoRendererTests.swift`
- `doc/current.md`
- `doc/devlog.md`

### Validation Results

- Ran 10 focused image and standard video regression tests with `xcodebuild`; all 10 passed with 0 failures.
- Passing coverage included final rounded-corner alpha pixels, preview-mask dimensions, PNG output, MP4 H.264 export, video orientation, native-player hosting, bitrate fallback, larger-canvas bitrate density, and the explicit source-bitrate floor.
- The app and test targets compiled successfully. Existing AVFoundation deprecation warnings remain.

### Risks or Follow-up Work

- End-to-end rounded-corner appearance with the user's imported frame remains a manual UI check.

## 2026-08-31 — Prevented Rounded Export Edge Gaps

### Change Summary

- Replaced the rectangular inverse-alpha mask with a central-aperture mask isolated from the device frame's full alpha channel.
- Expanded the isolated screen aperture by two final-output pixels, cropped it to `screenRect`, and retained the device-frame artwork as the final top layer so capture pixels extend beneath the bezel without exposing a seam.
- Excluded transparency connected to the outer frame boundary so rounded device corners remain clean even when the aperture bounding rectangle contains exterior-transparent pixels.
- Reused the prepared aperture mask for PNG composition, per-frame MOV composition, and video preview without changing public APIs, backgrounds, canvas presets, bitrate policy, codecs, or audio handling.
- Added synthetic final-PNG and encoded transparent-MOV pixel regressions plus an optional full-resolution regression using the locally imported iPhone 17 Pro Max frame.

### Affected Files

- `SimFrame/Services/ImageRenderer.swift`
- `SimFrame/Services/VideoRenderer.swift`
- `SimFrameTests/ImageRendererTests.swift`
- `SimFrameTests/TestImageFactory.swift`
- `SimFrameTests/VideoRendererTests.swift`
- `doc/current.md`
- `doc/devlog.md`

### Validation Results

- Ran 17 reproducible unit and media tests with `xcodebuild`; all 17 passed with 0 failures. The command excluded only the local 30-frame library scan and the local high-resolution HEVC with Alpha audio fixture.
- Ran four focused rounded-edge regressions; all four passed with 0 failures. They covered the exact two-pixel overlap, final synthetic PNG pixels, a full-resolution 1470 x 3000 PNG rendered with the locally imported iPhone 17 Pro Max Cosmic Orange frame, and alpha pixels read from an encoded short transparent MOV.
- Ran `./script/build_and_run.sh --verify`; the build succeeded and the updated app process was verified.
- Started a full test invocation, but interrupted it after the local 30-frame Apple library scan made no progress within a practical validation time. The high-resolution HEVC with Alpha local-fixture test was therefore not completed and is not recorded as passing.
- A separate UI-test attempt failed before executing the test because Xcode timed out while enabling automation mode.
- Existing AVFoundation deprecation warnings remain.

### Risks or Follow-up Work

- A post-fix visual inspection of PNG, transparent MOV, and video preview remains pending because the Mac was locked during the final UI validation attempt.
- The high-resolution HEVC with Alpha local-fixture test still needs a practical completion window before it can be recorded as passing.

## 2026-08-31 — Expanded Video Preview Controls to the Display Area

### Change Summary

- Separated video playback controls from the masked native player surface so control sizing no longer inherits the portrait device screen aperture width.
- Sized the playback bar from the complete available preview width with fixed horizontal margins and responsive window resizing.
- Added play/pause, seeking, elapsed and total time, and mute controls while preserving frame-derived video masking and non-interactive device-frame artwork.
- Added regression coverage proving that playback-control width comes from the preview area rather than the device screen aperture.

### Affected Files

- `SimFrame/Views/DropPreviewView.swift`
- `SimFrameTests/VideoRendererTests.swift`
- `doc/current.md`
- `doc/devlog.md`

### Validation Results

- Ran two focused playback-preview tests with `xcodebuild`; both passed with 0 failures.
- Ran 18 reproducible unit and media tests with `xcodebuild`; all 18 passed with 0 failures. The local 30-frame library scan and high-resolution HEVC with Alpha audio fixture were excluded.
- Ran `./script/build_and_run.sh --verify`; the build succeeded and the updated app process was verified.
- Inspected the running app with an iPhone 17 Pro Max portrait recording. The playback bar spanned the available preview area with 24-point horizontal margins, the video remained inside the screen aperture, and play/pause updated the elapsed time and slider position.

### Risks or Follow-up Work

- Pointer dragging of the seek slider and mute interaction remain manual checks; their controls compiled and were visible in the running app.

## 2026-08-31 — Bounded the Video Preview Control Width

### Change Summary

- Added a 400-point minimum and 1,000-point maximum to the responsive video playback control width.
- Preserved preview-area sizing between the two bounds and kept the existing 24-point horizontal inset calculation.
- Extended the layout regression to cover the minimum, responsive intermediate, and maximum width cases.

### Affected Files

- `SimFrame/Views/DropPreviewView.swift`
- `SimFrameTests/VideoRendererTests.swift`
- `doc/current.md`
- `doc/devlog.md`

### Validation Results

- Ran the focused playback-control width test with `xcodebuild`; it passed with 0 failures and verified 400-point minimum, 952-point intermediate, and 1,000-point maximum results.
- Ran 18 reproducible unit and media tests with `xcodebuild`; all 18 passed with 0 failures. The local 30-frame library scan and high-resolution HEVC with Alpha audio fixture were excluded.
- Ran `./script/build_and_run.sh --verify`; the build succeeded and the updated app process was verified.

### Risks or Follow-up Work

- The exact 400-point and 1,000-point extremes were verified by layout regression rather than manual window-resize inspection.

## 2026-08-31 — Enlarged Playback Buttons and Added the Space Shortcut

### Change Summary

- Increased the play/pause and mute controls to 30-point interaction targets with 17-point semibold system icons.
- Registered Space as the play/pause keyboard shortcut on the visible playback button so keyboard and pointer input share the same action.
- Updated the play/pause help text to expose the Space shortcut.
- Extended playback-control regression coverage for the new button and icon sizes.

### Affected Files

- `SimFrame/Views/DropPreviewView.swift`
- `SimFrameTests/VideoRendererTests.swift`
- `doc/current.md`
- `doc/devlog.md`

### Validation Results

- Ran two focused playback-preview tests with `xcodebuild`; both passed with 0 failures.
- Ran 18 reproducible unit and media tests with `xcodebuild`; all 18 passed with 0 failures. The local 30-frame library scan and high-resolution HEVC with Alpha audio fixture were excluded.
- Ran `./script/build_and_run.sh --verify`; the build succeeded and the updated app process was verified.
- Inspected the running app and confirmed that the larger play/pause and mute controls render correctly.
- Pressed Space in the running app twice. The first press changed Play to Pause and advanced the timeline; the second changed Pause back to Play and stopped at the current time.

### Risks or Follow-up Work

- None.

## 2026-08-31 — Removed the Main Window Status Footer

### Change Summary

- Removed the persistent footer below the main workspace, including its status message, progress indicator, frame count, format label, and divider.
- Preserved the preview, recent captures, inspector, toolbar actions, alerts, and underlying application state.

### Affected Files

- `SimFrame/Views/MainView.swift`
- `doc/current.md`
- `doc/devlog.md`

### Validation Results

- Ran `./script/build_and_run.sh --verify`; the macOS app target built successfully, launched, and passed process verification.
- Inspected the running SimFrame window with an existing video capture. The workspace ended at the recent-captures area with no footer, divider, status message, progress indicator, frame count, or format label.
- Confirmed that the preview, playback controls, recent captures, inspector, and toolbar remained visible.

### Risks or Follow-up Work

- None.

## 2026-08-31 — Prevented Space-Key Pause from Resuming

### Change Summary

- Confirmed that pointer-driven pause remains stable and isolated the automatic resume behavior to the SwiftUI button shortcut path.
- Replaced the button-level Space shortcut with a narrow, window-scoped AppKit key-down bridge that invokes the existing SwiftUI playback action.
- Consumed unmodified Space events, ignored automatic key repeats, and allowed modified or unrelated key events to continue through the responder chain.
- Added regression coverage for a single unmodified Space press, repeated Space events, modified Space events, and unrelated keys.

### Affected Files

- `SimFrame/Views/DropPreviewView.swift`
- `SimFrameTests/VideoRendererTests.swift`
- `doc/current.md`
- `doc/devlog.md`

### Validation Results

- Ran three focused playback-preview tests with `xcodebuild`; all 3 passed with 0 failures.
- Ran 19 reproducible unit and media tests with `xcodebuild`; all 19 passed with 0 failures. The local 30-frame library scan and high-resolution HEVC with Alpha audio fixture were excluded.
- Ran `./script/build_and_run.sh --verify`; the build succeeded and the updated app process was verified.
- Inspected the running app with a recent video capture. Space started playback, the next Space press paused at 8.072011667 seconds, and the timeline remained unchanged after a three-second wait.

### Risks or Follow-up Work

- None.

## 2026-08-31 — Simplified the Main Toolbar

### Change Summary

- Removed the duplicate Export action from the top-right toolbar.
- Kept the toolbar focused on opening capture media and selecting the device-frame library.
- Preserved the Export action and format controls in the inspector.

### Affected Files

- `SimFrame/Views/MainView.swift`
- `doc/current.md`
- `doc/devlog.md`

### Validation Results

- Ran `./script/build_and_run.sh --verify`; the macOS app target built successfully, launched, and passed process verification.
- Inspected the running app's accessibility hierarchy and confirmed that the toolbar contains only Open Capture and Frame Library.
- Confirmed that Export remains available in the inspector and no longer appears in the toolbar.

### Risks or Follow-up Work

- None.

## 2026-08-31 — Removed Device Frame Switching Stalls

### Change Summary

- Precomputed an alpha-derived outer-screen mask for every imported frame and added automatic repair for missing, corrupt, or dimensionally invalid masks in existing libraries without changing the manifest schema.
- Filled Dynamic Island, notch, and camera occlusions inside the mask while preserving rounded exterior transparency and the two-pixel bezel overlap; device artwork remains the top layer that covers internal hardware regions.
- Added a deterministic 128 MB decoded-byte LRU for frame artwork and masks, with complete invalidation after library replacement and per-frame invalidation after metadata edits.
- Moved production frame loading, mask reads, still-preview rendering, full-resolution clipboard rendering, and Core Image output away from the main actor.
- Added cancellable frame-load, preview, copy, and resize-debounce tasks plus request-generation checks so stale work cannot replace the latest selection.
- Rendered still-image previews to the actual viewport pixel size after a 150 ms resize debounce without upscaling, while retaining full resolution for PNG export and clipboard copy.
- Updated image, video-preview, and video-export paths to share the same decoded artwork and precomputed mask.

### Affected Files

- `SimFrame/App/SimFrameApp.swift`
- `SimFrame/Models/Models.swift`
- `SimFrame/Services/FrameLibraryService.swift`
- `SimFrame/Services/ImageRenderer.swift`
- `SimFrame/Services/VideoRenderer.swift`
- `SimFrame/Stores/AppState.swift`
- `SimFrame/Views/DropPreviewView.swift`
- `SimFrame/Views/InspectorView.swift`
- `SimFrameTests/DeviceDetectorTests.swift`
- `SimFrameTests/FrameLibraryTests.swift`
- `SimFrameTests/ImageRendererTests.swift`
- `SimFrameTests/TestImageFactory.swift`
- `SimFrameTests/VideoRendererTests.swift`
- `doc/current.md`
- `doc/devlog.md`

### Validation Results

- Ran all 28 unit and media tests with `xcodebuild`; all 28 passed with 0 failures in 81.481 seconds. The run included the local 30-frame scan, full-resolution iPhone 17 Pro Max PNG, transparent MOV, audio, codec, bitrate, Dynamic Island, connected-notch, cache-repair, viewport-size, and stale-request regressions.
- Ran the full macOS test command. All 28 unit and media tests passed, but the onboarding UI test failed its three element assertions because the automation-launched app process did not create a window. Rerunning the UI test alone produced the same environment-specific result.
- Ran `./script/build_and_run.sh --verify` after the final observation fix; the target built, launched, and passed process verification.
- Inspected the running app with real PNG and video captures. The existing library automatically reached 30 valid masks, rounded clipping remained clean, Dynamic Island was covered by the top-layer artwork, full-resolution Copy became enabled after assets loaded, rapid Device and Variant changes settled on the latest selection, and window zoom and restore preserved a ready preview.
- Captured an eight-second rapid-switch `sample`. The main thread contained no screen-alpha flood-fill, mask generation, or full-resolution Core Image output; observed PNG decoding ran on SwiftUI's background `prepare-image` queue.
- Existing AVFoundation deprecation warnings remain.

### Risks or Follow-up Work

- The onboarding UI test needs reevaluation when the macOS 27/Xcode automation environment can launch the app with a window.
- A first launch that must build all masks for an existing high-resolution 30-frame library can temporarily remain on onboarding; this one-time migration completed successfully in the current local library.

## 2026-08-31 — Preserved Video Position During Frame Changes

### Change Summary

- Moved elapsed time, duration, playback, seeking, and mute state out of the transient playback-controls view into an application-owned playback controller.
- Made Device, Orientation, and Variant changes pause the active video at its exact current position without publishing an intermediate zero value.
- Kept the native video surface and playback controls mounted while replacement frame artwork and masks load; only the frame-dependent visual layers now show the preparing placeholder.
- Preserved the existing outer-screen mask behavior so Dynamic Island, notch, and camera regions remain part of the content aperture and are covered by the final top-layer device artwork.

### Affected Files

- `SimFrame/Stores/AppState.swift`
- `SimFrame/Views/DropPreviewView.swift`
- `SimFrameTests/VideoRendererTests.swift`
- `doc/current.md`
- `doc/devlog.md`

### Validation Results

- Ran four focused playback and mask regressions with `xcodebuild`; all 4 passed with 0 failures. This included the new nonzero playback-position test plus Dynamic Island and connected-notch coverage.
- Ran all 29 unit and media tests with the full macOS test command; all 29 passed with 0 failures in 39.021 seconds. The run included the local 30-frame Apple library scan, full-resolution iPhone 17 Pro Max PNG regression, and local HEVC with Alpha audio fixture.
- The full command's onboarding UI test failed before assertions because Xcode attempted to terminate a stale reported SimFrame PID. Ending the manually launched app and rerunning the UI test alone reproduced the same automation failure.
- Ran `./script/build_and_run.sh --verify`; the macOS app target built successfully, launched, and passed process verification.
- Inspected the running app with a real 11.6-second video. Starting at 4.5 seconds and changing Variant during playback paused at 5.896 seconds; Device and Orientation changes then retained 5.896 seconds, the paused state, and the visible controls. The preview also showed content beneath Dynamic Island while the top-layer artwork covered the hardware region.

### Risks or Follow-up Work

- The onboarding UI test still needs reevaluation when the macOS 27/Xcode automation runner stops targeting a stale application process.

## 2026-08-31 — Reduced Frame Import CPU and Memory Cost

### Change Summary

- Replaced two independent frame decodes and central-aperture scans with one shared alpha analysis per source PNG.
- Extracted the source Alpha channel directly into a single-channel buffer instead of rendering and retaining a four-channel RGBA inspection buffer.
- Reused the central aperture flood-fill result for both frame metadata and mask generation.
- Replaced generic integer flood-fill queues with fixed-width work storage and pointer-based hot loops, while preserving bounds and one-visit-per-pixel behavior.
- Removed a redundant full-frame dilation output and an extra cropped-mask byte copy.
- Wrapped every imported or repaired frame in an autorelease pool so temporary Core Graphics and ImageIO objects are released before processing the next frame.
- Added compact-analysis and optional real 30-frame import regressions.

### Affected Files

- `SimFrame/Services/FrameLibraryService.swift`
- `SimFrame/Services/ImageRenderer.swift`
- `SimFrameTests/FrameLibraryTests.swift`
- `doc/current.md`
- `doc/devlog.md`

### Validation Results

- Ran four focused compact-analysis, rounded-screen, Dynamic Island, and connected-notch tests after the final pointer-only hot-loop cleanup; all 4 passed with 0 failures in 0.321 seconds.
- Ran the real local 30-frame Debug import regression. The final full-suite run completed the import in 84.049 seconds and created all 30 masks. An earlier same-test intermediate implementation took 114.544 seconds before the sampled hot loops were optimized.
- Sampled the final 30-frame import for five seconds. The process used one background CPU core, reported a 73.6 MB physical footprint and a 103.5 MB peak, and showed approximately 119 MB RSS at the command-line snapshot. The earlier unoptimized running-app sample had reported approximately 401 MB RSS and a 913.2 MB peak physical footprint.
- Ran the full macOS test command before the final pointer-only span and dilation loop cleanup. All 31 unit and media tests passed with 0 failures in 100.368 seconds. The UI test failed before assertions because Xcode again attempted to terminate the stale suspended SimFrame PID `12047`.
- Ran the final unit/media command with the two existing `Downloads`-backed fixture tests excluded after both blocked in host file access at 0% CPU. The remaining run executed 29 tests with the opt-in import benchmark skipped and 0 failures in 3.007 seconds. Dynamic Island, connected notch, rounded clipping, playback-position preservation, PNG output, and video export coverage all passed.
- Ran `./script/build_and_run.sh --verify` after the final hot-loop cleanup; the macOS app built, launched, and passed process verification. The prior new idle app process reported 0% CPU and approximately 122 MB RSS.

### Risks or Follow-up Work

- A first import or missing-mask repair still performs full-resolution Alpha analysis and PNG encoding on one background CPU core. This work is intentionally completed once and cached.
- The onboarding UI test still needs reevaluation after the macOS 27/Xcode runner stops targeting the stale suspended application process.
- Two existing local-fixture tests could not be repeated after the final hot-loop cleanup because this host blocked while accessing their Apple artwork under `Downloads`; an earlier full run passed both.

## 2026-08-31 — Added Device Frame Import Progress

### Change Summary

- Added concurrent import phases for scanning, determinate per-file preparation, installation, first-frame loading, and cancellation cleanup.
- Made Device Frame library import asynchronous with monotonic progress callbacks and cancellation checks around directory enumeration, every candidate PNG, and atomic installation.
- Added application-owned import task and request-generation state to reject duplicate imports and stale callbacks, pause video without resetting its timeline, and keep the overlay visible until the first artwork and mask are ready.
- Added a centered window-level material overlay that preserves the old preview underneath while disabling the workspace, inspector, toolbar, drag-and-drop surface, and Device Frame Pickers.
- Added safe cancellation before installation. The staging library is removed before the overlay closes, and the existing manifest, frames, and masks remain installed after cancellation or failure.

### Affected Files

- `SimFrame/Models/Models.swift`
- `SimFrame/Services/FrameLibraryService.swift`
- `SimFrame/Stores/AppState.swift`
- `SimFrame/Views/MainView.swift`
- `SimFrameTests/FrameLibraryTests.swift`
- `doc/current.md`
- `doc/devlog.md`

### Validation Results

- Ran the four initial focused import regressions; all 4 passed with 0 failures in 0.513 seconds. Coverage included monotonic progress through an invalid PNG, cancellation cleanup with exact existing-library preservation, duplicate-request blocking, first-frame loading, and stale callback rejection.
- Added and ran a focused first-frame asset failure regression; it passed with 0 failures in 0.085 seconds and confirmed that the overlay closes while the load error is presented.
- Ran the final complete unit/media suite; all 36 tests executed with 1 opt-in import benchmark skipped and 0 failures in 11.747 seconds. The local iPhone 17 scan, rounded frame, transparent MOV, audio, mask, rendering, playback, and import regressions all passed.
- Ran the full macOS test command before the final failure-path test was added. Its then-current 35 unit/media tests passed with 1 skip and 0 failures, but the onboarding UI test failed before assertions because Xcode could not terminate stale reported SimFrame PID `78349`.
- Ran `./script/build_and_run.sh --verify`; the target built successfully, launched, and passed process verification.
- Inspected the running app while replacing the real 30-frame library. The window-level overlay appeared immediately, disabled the underlying workspace and toolbar, showed determinate progress at `0 of 30` and `19 of 30`, and remained until the new selection was usable. A second import cancelled safely and continued to show the existing library.
- Opened a real video, sought to a nonzero position, started playback, and began a library replacement. Import paused the video with its controls visible beneath the overlay, and cancellation retained the 11.62-second timeline position.

### Risks or Follow-up Work

- The onboarding UI test remains blocked by the existing Xcode stale-process termination problem; the running app and import overlay were inspected directly instead.
