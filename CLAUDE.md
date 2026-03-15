# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is this?

open-wispr is a local, privacy-focused voice dictation app for macOS. Push-to-talk records audio, transcribes it on-device (Whisper or GigaAM), and pastes text at the cursor. No cloud dependencies — everything runs locally on Apple Silicon.

## Build & Run

```bash
# Build from source
swift build -c release

# Build with Metal shader support + install to /Applications/OpenWispr.app
bash build.sh

# Development cycle (configure, build, bundle, launch)
bash scripts/dev.sh

# Release: sign with Developer ID + create DMG (output in dist/)
bash scripts/release.sh

# Release with notarization (required for public distribution)
APPLE_ID="email" APP_PASSWORD="xxxx-xxxx-xxxx-xxxx" bash scripts/release.sh
```

## Tests

```bash
# Unit tests
swift test

# Run a single test
swift test --filter OpenWisprTests.ConfigTests
swift test --filter OpenWisprTests.ConfigTests/testFlexBoolDecoding

# Integration tests
bash scripts/test-install.sh        # CLI smoke tests + shellcheck
bash scripts/test-transcription.sh  # Requires whisper-cpp (brew install whisper-cpp)
```

CI runs 4 parallel jobs on PRs: build, unit-tests, install-test, transcription-test (see `.github/workflows/ci.yml`).

## Architecture

**Core flow:** hotkey press → AudioRecorder captures 16kHz mono → transcription engine → TextPostProcessor (spoken punctuation) → TextInserter (paste at cursor via Cmd+V simulation)

**Two transcription engines:**
- **Whisper** (`Transcriber.swift`): spawns `whisper-cpp` as a subprocess, parses stdout. Multi-language, 9 model sizes.
- **GigaAM** (`GigaAMTranscriber.swift` + `GigaAM/`): native MLX inference on Apple Silicon. Russian-optimized, supports streaming/live transcription.

**Key components in `Sources/OpenWisprLib/`:**
- `AppDelegate.swift` — orchestrates the entire hotkey → record → transcribe → insert pipeline
- `HotkeyManager.swift` — global NSEvent monitor for modifier keys and key chords
- `AudioRecorder.swift` — AVAudioEngine recording with streaming sample callback
- `TextInserter.swift` — pasteboard save/restore + simulated Cmd+V keystroke
- `Config.swift` — JSON config at `~/.config/open-wispr/config.json`; uses `FlexBool` (accepts bool/string/int)
- `StatusBarController.swift` — menu bar icon, animation, recording list
- `StreamingOverlay.swift` — glassmorphism HUD for real-time transcription feedback

**CLI entry point:** `Sources/OpenWispr/main.swift` — subcommands: `start`, `set-hotkey`, `get-hotkey`, `set-model`, `set-engine`, `download-model`, `status`, `test-gigaam`

## Release & Distribution

Distributed outside the App Store (notarized DMG). App Sandbox is incompatible with core functionality (global hotkey monitoring, CGEvent paste simulation, Accessibility API).

- **Signing identity:** `Developer ID Application: Aleksandr Bobrov (8HR3ZJZ5MZ)`
- **Bundle ID:** `com.human37.open-wispr`
- **Release script:** `scripts/release.sh` — builds, signs, creates DMG, optionally notarizes
- **Output:** `dist/OpenWispr-{version}.dmg`

## Platform & Dependencies

- macOS 14.0+ (Sonoma), Apple Silicon only
- Swift 6.0 (v5 language mode), SPM
- Primary dependency: `mlx-swift` (MLX, MLXNN, MLXFFT) for on-device ML inference
- Linked frameworks: CoreAudio, AVFoundation, AppKit
- External tool: `whisper-cpp` (Homebrew) for Whisper engine

## Guidelines

- No cloud dependencies — everything must run on-device
- Test on Apple Silicon (Intel not supported)
- New pure logic → add unit test in `Tests/OpenWisprTests/`
- New CLI commands → add assertions to `scripts/test-install.sh`
- New shell scripts → add to shellcheck list in `test-install.sh`
