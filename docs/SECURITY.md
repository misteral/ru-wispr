# Security

## Privacy Model

RuWispr is completely local. No audio or text ever leaves the machine.

- Audio is recorded to a temp file, transcribed on CPU/GPU, temp file deleted
- No network requests except model download on first run
- Optional local recording storage (`maxRecordings` setting) — stays on-device

## Required Permissions

| Permission | Why | Consequence if missing |
|---|---|---|
| **Microphone** | Audio recording | Cannot record — lock icon in menu bar |
| **Accessibility** | Global hotkey monitoring, CGEvent paste simulation | Cannot detect hotkey or paste text |

## Secrets

- **Signing identity** and Apple ID credentials for notarization are never committed to the repo
- Notarization credentials passed via environment variables: `APPLE_ID`, `APP_PASSWORD`
- No API keys in source code — the app has zero cloud dependencies

## Boundary Rules

- All user input (config JSON) is parsed with explicit types and defaults
- `FlexBool` handles flexible user input (bool/string/int) without crashing
- Missing or malformed config fields fall back to defaults, never crash
