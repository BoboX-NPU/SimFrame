# SimFrame Project Collaboration Guidelines

All project collaboration documentation must be written in English. Filenames, code identifiers, commands, and technical terms should retain their original spelling.

## Before Starting a Task

- Read `doc/current.md` first and use the current project state recorded there as the working baseline.
- Review `doc/devlog.md` when historical changes, previous validation, or earlier issues are relevant.
- Treat the code, configuration, and actual validation results as the source of truth. If the documentation does not match the project, correct the documentation in the same task.

## After Every Project Update

Any change to code, configuration, scripts, tests, resources, or project documentation must include all of the following updates in the same task:

1. Update `doc/current.md` so it accurately describes the resulting current project state.
2. Append a record of the change to the end of `doc/devlog.md`.
3. After documentation and validation are complete, create a Git commit for the finished change.

## Git Commit Format

- Use a short, simple English title that summarizes the change.
- Use the following English template for every commit message body, replacing `xxx` with concise descriptions:

```text
New Features

- xxx

Improvements

- xxx

Bug Fixes

- Various bug fixes and performance improvements
```
- Stage only files that belong to the completed change. Review the staged diff before committing.
- Do not claim validation, features, improvements, or fixes that were not actually completed.

## Documentation Maintenance Rules

- `doc/current.md` must contain only the currently valid project state, capabilities, constraints, and outstanding work. Replace outdated information instead of accumulating history in this file.
- `doc/devlog.md` is append-only. Add new entries at the end and do not rewrite or delete existing entries. If an earlier entry needs correction, append a correction entry.
- Every devlog entry must include the date, change summary, affected files, validation results, and remaining risks or follow-up work. Write `None` when there are no known items.
- Record validation results accurately. If no build or tests were run, explicitly state `Not run`; do not present historical results as results from the current task.
