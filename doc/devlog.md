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
