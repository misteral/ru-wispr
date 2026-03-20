# Architecture

## Overview

RuWispr is a local voice dictation app for macOS. Push-to-talk records audio, transcribes it on-device, and pastes text at the cursor. No cloud dependencies — everything runs locally on Apple Silicon.

**Core flow:** hotkey press → `AudioRecorder` captures 16kHz mono → transcription engine → `TextPostProcessor` (spoken punctuation) → `TextInserter` (paste at cursor via Cmd+V simulation)

## Package Map

| Target | Path | Description |
|---|---|---|
| `RuWisperLib` | `Sources/RuWisperLib/` | Core library — audio, transcription, UI, config |
| `ru-wisper` | `Sources/RuWisper/` | CLI entry point (`main.swift`) |
| `RuWisperTests` | `Tests/RuWisperTests/` | Unit tests for the library |

### RuWisperLib Components

| File | Responsibility |
|---|---|
| `AppDelegate.swift` | Orchestrates the hotkey → record → transcribe → insert pipeline |
| `HotkeyManager.swift` | Global NSEvent monitor for modifier keys and key chords |
| `AudioRecorder.swift` | AVAudioEngine recording with streaming sample callback |
| `AudioLevelHistory.swift` | Audio level tracking for waveform visualization |
| `Transcriber.swift` | Whisper engine — spawns `whisper-cpp` as subprocess, parses stdout |
| `GigaAMTranscriber.swift` | GigaAM engine — native MLX inference on Apple Silicon |
| `GigaAM/GigaAMModel.swift` | GigaAM neural network model definition |
| `GigaAM/GigaAMConfig.swift` | GigaAM model configuration |
| `TextPostProcessor.swift` | Spoken punctuation replacement and text cleanup |
| `TextInserter.swift` | Pasteboard save/restore + simulated Cmd+V keystroke |
| `Config.swift` | JSON config in iCloud Drive (`~/Library/Mobile Documents/com~apple~CloudDocs/RuWispr/config.json`); `FlexBool` (accepts bool/string/int); auto-migrates from legacy `~/.config/ru-wisper/` |
| `ModelDownloader.swift` | Whisper model download from HuggingFace |
| `StatusBarController.swift` | Menu bar icon, animation, recording list |
| `StreamingOverlay.swift` | Glassmorphism HUD for real-time transcription feedback |
| `NotchOverlay.swift` | Notch-area overlay using DynamicNotchKit |
| `WaveformView.swift` | Audio waveform visualization |
| `RecordingStore.swift` | Recording file history, listing, sorting, pruning |
| `Permissions.swift` | Microphone and accessibility permission checks |
| `KeyCodes.swift` | Key name/code mapping and parsing |
| `L10n.swift` | Localization strings |
| `Version.swift` | Version constant |

## Transcription Engines

Two engines, switchable via config:

### Whisper (`Transcriber.swift`)
- Spawns `whisper-cpp` (Homebrew) as a subprocess
- Parses stdout for transcription text
- Multi-language, 9 model sizes (tiny → large)
- Requires external binary: `brew install whisper-cpp`

### GigaAM (`GigaAMTranscriber.swift` + `GigaAM/`)
- Native MLX inference on Apple Silicon via `mlx-swift`
- Russian-optimized, supports streaming/live transcription
- No external dependencies — model weights downloaded on first use

## Dependency Rules

- `ru-wisper` (CLI) depends on `RuWisperLib` only
- `RuWisperLib` external deps: `mlx-swift` (MLX, MLXNN, MLXFFT), `DynamicNotchKit`
- Linked frameworks: CoreAudio, AVFoundation, AppKit
- External tool: `whisper-cpp` (Homebrew) — runtime dependency for Whisper engine only

## CLI Subcommands

Entry point: `Sources/RuWisper/main.swift`

| Command | Description |
|---|---|
| `start` | Launch the app |
| `set-hotkey` | Change the push-to-talk hotkey |
| `get-hotkey` | Print current hotkey |
| `set-model` | Change Whisper model size |
| `set-engine` | Switch between Whisper and GigaAM |
| `download-model` | Pre-download a Whisper model |
| `status` | Print running status |
| `test-gigaam` | Test GigaAM transcription |

## Platform Requirements

- macOS 14.0+ (Sonoma)
- Apple Silicon only (Intel not supported)
- Swift 6.0 (v5 language mode), SPM
