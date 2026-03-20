# AGENTS.md

RuWispr — local, privacy-focused voice dictation for macOS. Push-to-talk records audio, transcribes on-device (Whisper via whisper-cpp or GigaAM via MLX), and pastes text at the cursor. No cloud dependencies — everything runs on Apple Silicon.

This file is a map. Full documentation lives in `docs/`. Read the relevant doc before starting any task.

## Documentation Index

| File | Contents |
|---|---|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Package map, component list, transcription engines, CLI commands |
| [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) | Dev setup, PR workflow, branch strategy, git rules |
| [docs/CODING_STANDARDS.md](docs/CODING_STANDARDS.md) | Swift style, forbidden patterns, config handling |
| [docs/TESTING.md](docs/TESTING.md) | Unit tests, integration tests, CI, writing tests |
| [docs/RELEASING.md](docs/RELEASING.md) | Signing, notarization, DMG build, versioning |
| [docs/SECURITY.md](docs/SECURITY.md) | Privacy model, permissions, secrets |
| [docs/RELIABILITY.md](docs/RELIABILITY.md) | Performance constraints, error handling, resource management |
| [docs/QUALITY_SCORE.md](docs/QUALITY_SCORE.md) | Per-component quality grades and known gaps |
| [docs/design-docs/core-beliefs.md](docs/design-docs/core-beliefs.md) | Agent-first operating principles |
| [docs/design-docs/index.md](docs/design-docs/index.md) | All design decisions |
| [docs/product-specs/index.md](docs/product-specs/index.md) | Product specifications |
| [docs/exec-plans/tech-debt-tracker.md](docs/exec-plans/tech-debt-tracker.md) | Known tech debt |

## Quick Commands

```bash
swift build -c release          # Build
swift test                      # Unit tests
bash scripts/dev.sh             # Full dev cycle (configure, build, bundle, launch)
bash scripts/test-install.sh    # Integration tests + shellcheck
bash scripts/release.sh         # Sign + create DMG
```

## First Message

If the user did not give a concrete task: read `README.md` and `docs/ARCHITECTURE.md`, then ask which area to work on. Based on the answer, read the relevant `docs/` file.

## Critical Rules

- **No cloud dependencies** — everything must run on-device. No network calls except model download on first run.
- **Apple Silicon only** — no Intel fallbacks, no x86 code paths.
- **Test before committing** — run `swift test` at minimum. For CLI/script changes, also run `bash scripts/test-install.sh`.
- **No secrets in code** — signing identity and notarization credentials via env vars only.
- **New pure logic → unit test** in `Tests/RuWisperTests/`. New CLI commands → assertions in `scripts/test-install.sh`. New scripts → add to shellcheck list.
