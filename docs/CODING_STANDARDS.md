# Coding Standards

## Language & Toolchain

- Swift 6.0 with v5 language mode
- SPM (Swift Package Manager) for dependencies
- macOS 14.0+ deployment target

## Style

- Follow existing code style in the project
- Match Apple's Swift naming conventions
- Keep files focused — one major type per file

## Forbidden Patterns

- **No cloud/network calls** — everything must run on-device (exception: model download on first run)
- **No hardcoded secrets** — API keys, tokens, passwords never in source code
- **No Intel-specific code** — Apple Silicon only, no x86 fallbacks
- **No App Sandbox** — incompatible with core functionality (global hotkey monitoring, CGEvent paste simulation, Accessibility API)

## Config & Data Paths

- **Config** (synced via iCloud): `~/Library/Mobile Documents/com~apple~CloudDocs/RuWispr/config.json`
- **Data** (local, large files): `~/Library/Application Support/RuWispr/` — models, recordings
- Legacy path `~/.config/ru-wisper/` auto-migrated on first launch
- Use `Config.configDir` for config, `Config.dataDir` for models/recordings
- Use `FlexBool` type for boolean config values (accepts bool/string/int for user-friendliness)
- All config fields must have sensible defaults

## Error Handling

- Gracefully handle missing permissions (microphone, accessibility)
- Show user-friendly status in menu bar (lock icon for missing permissions)
- Never crash on missing external tools (whisper-cpp) — show clear error state instead
