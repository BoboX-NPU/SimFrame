# SimFrame

SimFrame is a local-first macOS utility that places iOS Simulator screenshots and recordings inside user-imported Apple product bezels.

## Run

```bash
./script/build_and_run.sh
```

Import the extracted PNG folder from Apple Design Resources on first launch. Apple artwork is copied into the app's Application Support directory and is intentionally excluded from this repository.

## Test

```bash
xcodebuild -project SimFrame.xcodeproj -scheme SimFrame -destination 'platform=macOS' test
```

`script/generate_validation_fixtures.sh` creates an exact-size iPhone 17 Pro image and two-second video with audio for local validation. The generated files are ignored by Git.

