# Quality Score

Tracks quality grade per component. Updated periodically.

| Component | Grade | Notes |
|---|---|---|
| Audio recording | B | Solid, but no tests for AVAudioEngine layer |
| Whisper transcription | B | Works well, depends on external `whisper-cpp` binary |
| GigaAM transcription | B | Native MLX, Russian-optimized, streaming support |
| Text insertion | B | Pasteboard save/restore works, but Cmd+V simulation can fail in some apps |
| Config handling | A | Well-tested, `FlexBool` flexibility, good defaults |
| Hotkey detection | B | Works globally, but CGEvent tap can be disabled by macOS security |
| Menu bar UI | B | Animated states, recording list, functional |
| Streaming overlay | B | Glassmorphism HUD, real-time feedback |
| Unit tests | B | Good coverage of pure logic (Config, TextPostProcessor, KeyCodes, RecordingStore) |
| Integration tests | B | CLI smoke tests + transcription tests, shellcheck |
| CI | A | 4 parallel jobs, Swift-change detection for skip optimization |
