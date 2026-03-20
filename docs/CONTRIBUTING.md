# Contributing

## Development Setup

```bash
# Full dev cycle: configure, build, bundle, launch
bash scripts/dev.sh
```

The dev script handles:
1. **Configure** — prompts for Whisper model size, language, spoken punctuation, hotkey
2. **Clean up** — stops running instances, removes Homebrew version if present
3. **Build** — `swift build -c release`
4. **Bundle** — packages into `RuWispr.app`, copies to `~/Applications/`
5. **Start** — launches the app for testing

## PR Workflow

1. Create a branch off `main`
2. Make changes
3. Run tests: `swift test && bash scripts/test-install.sh`
4. Test locally with `bash scripts/dev.sh`
5. Open a pull request against `main`

CI runs automatically on PRs (see [TESTING.md](TESTING.md) for CI details).

## Branch Strategy

- `main` — stable, release-ready branch
- Feature branches off `main` — short-lived, focused PRs

## Commit Conventions

- Clear, descriptive commit messages
- Reference issue numbers where applicable

## Git Rules

- Never force-push to `main`
- Rebase feature branches on `main` before merging
- Keep PRs focused — one feature or fix per PR

## Guidelines

- Keep it simple — RuWispr is intentionally minimal
- No cloud dependencies — everything must run on-device
- Test on Apple Silicon (Intel not supported)
- Match the existing code style
- Include tests for new or changed logic (see [TESTING.md](TESTING.md))
