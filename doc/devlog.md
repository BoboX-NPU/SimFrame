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
