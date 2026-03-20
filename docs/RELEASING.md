# Releasing

## Distribution

Distributed outside the App Store as a notarized DMG. App Sandbox is incompatible with core functionality.

- **Signing identity:** `Developer ID Application: Aleksandr Bobrov (8HR3ZJZ5MZ)`
- **Bundle ID:** `co.itbeaver.ru-wisper`
- **Output:** `dist/RuWispr-{version}.dmg`

## Build & Release Commands

```bash
# Build from source
swift build -c release

# Build with Metal shader support + install to /Applications/RuWispr.app
bash build.sh

# Release: sign with Developer ID + create DMG (output in dist/)
bash scripts/release.sh

# Release with notarization (required for public distribution)
APPLE_ID="email" APP_PASSWORD="xxxx-xxxx-xxxx-xxxx" bash scripts/release.sh
```

## Release Steps

1. Update version in `Sources/RuWisperLib/Version.swift`
2. Run full test suite: `swift test && bash scripts/test-install.sh`
3. Run `bash scripts/release.sh` (with notarization env vars for public release)
4. Verify the DMG opens and app launches correctly
5. Upload DMG to GitHub Releases
6. Tag the release in git

## Versioning

- Semantic versioning (major.minor.patch)
- Patch: bug fixes, minor improvements
- Minor: new features, new CLI commands
- Major: breaking changes to config format, engine changes

## Scripts

| Script | Purpose |
|---|---|
| `build.sh` | Build with Metal shaders, install to /Applications |
| `scripts/release.sh` | Sign with Developer ID, create DMG, optionally notarize |
| `scripts/bundle-app.sh` | Create macOS .app bundle |
| `scripts/deploy.sh` | Release automation |
| `scripts/dev.sh` | Development cycle (configure, build, bundle, launch) |
