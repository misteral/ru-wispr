# Reliability

## Performance Constraints

- Transcription must start immediately after hotkey release — no perceptible delay
- Audio recording at 16kHz mono — minimal resource usage during recording
- Whisper engine: model size determines latency (tiny = fastest, large = slowest)
- GigaAM engine: supports streaming/live transcription for real-time feedback

## Error Handling

- Missing `whisper-cpp` binary → clear error state, not a crash
- Missing permissions → lock icon in menu bar, guided setup on first run
- Failed transcription → no text inserted, error shown in overlay
- Config parse failure → fall back to defaults for all fields
- Model download failure → retry with clear status indication

## Resource Management

- Audio temp files are deleted after transcription
- Recording history capped by `maxRecordings` (default 0 = no storage)
- Pasteboard state saved and restored around Cmd+V simulation
- Audio engine properly stopped when not recording
