# Testing

## Running Tests

### Unit Tests

```bash
swift test
```

Run a single test:
```bash
swift test --filter RuWisperTests.ConfigTests
swift test --filter RuWisperTests.ConfigTests/testFlexBoolDecoding
```

### Integration Tests

```bash
# CLI smoke tests + shellcheck on all scripts
bash scripts/test-install.sh

# Transcription test (requires whisper-cpp)
brew install whisper-cpp
bash scripts/test-transcription.sh
```

## Test Structure

### Unit Tests (`Tests/RuWisperTests/`)

Pure logic tests with no external dependencies.

| File | Covers |
|---|---|
| `ConfigTests.swift` | Config decoding, `effectiveMaxRecordings` clamping, `FlexBool` parsing, `HotkeyConfig` modifier flags |
| `RecordingStoreTests.swift` | Recording file creation, listing, sorting, pruning, deletion |
| `TextPostProcessorTests.swift` | Spoken punctuation replacement, spacing fixes, edge cases |
| `KeyCodesTests.swift` | Key name/code mapping, `parse()`, `describe()`, round-trip consistency |
| `GigaAMTests.swift` | GigaAM model tests |

### Integration Tests (`scripts/`)

**Install smoke test** (`test-install.sh`):
- Builds from source and verifies the binary
- Tests all CLI commands (`--help`, `status`, `get-hotkey`, `set-hotkey`, `set-model`)
- Validates error handling for invalid inputs
- Bundles the app and checks the `.app` structure
- Runs shellcheck on all shell scripts

**Transcription test** (`test-transcription.sh`):
- Generates test audio using macOS `say` + `afconvert`
- Runs whisper-cpp on the generated audio
- Verifies transcription output contains expected words
- Tests the binary's whisper-cpp detection

## CI

GitHub Actions (`.github/workflows/ci.yml`) runs on PRs to `main`. Four parallel jobs:

| Job | What it does |
|---|---|
| `build` | `swift build -c release` (skipped if no Swift files changed) |
| `unit-tests` | `swift test` (skipped if no Swift files changed) |
| `install-test` | Builds binary, tests CLI, bundles app, shellcheck |
| `transcription-test` | Installs whisper-cpp, builds, runs transcription tests |

## Writing Tests

### When to add unit tests
- New pure logic (parsing, transformations, config handling) → `Tests/RuWisperTests/`
- Good candidates: pure functions, data transformations, anything without hardware (microphone, display, accessibility)

### When to add integration tests
- New CLI commands → add assertions to `scripts/test-install.sh`
- Changes to transcription pipeline → add cases to `scripts/test-transcription.sh`
- New shell scripts → add the script path to the shellcheck list in `test-install.sh`

## Running Checks Before Commit

```bash
swift test
bash scripts/test-install.sh
```
