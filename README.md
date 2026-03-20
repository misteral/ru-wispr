<p align="center">
  <img src="logo.svg" width="80" alt="RuWispr logo">
</p>

<h1 align="center">RuWispr</h1>

<p align="center">
  Local, private voice dictation for macOS. Hold a key, speak, release — your words appear at the cursor.<br>
  Everything runs on-device. No audio or text ever leaves your machine.
</p>

<p align="center">Powered by <a href="https://github.com/ggml-org/whisper.cpp">whisper.cpp</a> and <a href="https://github.com/salute-developers/GigaAM">GigaAM</a> with Metal acceleration on Apple Silicon.</p>

## Install

Download the latest DMG from [Releases](https://github.com/ABorovenskoy/ru-wispr/releases), open it, and drag RuWispr to Applications.

A waveform icon appears in your menu bar when it's running.

The default hotkey is the **Globe key** (🌐, bottom-left). Hold it, speak, release.

> **[Full installation guide](docs/install-guide.md)** — permissions walkthrough with screenshots, non-English macOS instructions, and troubleshooting.

## Configuration

Edit `~/Library/Mobile Documents/com~apple~CloudDocs/RuWispr/config.json` (synced via iCloud Drive):

```json
{
  "hotkey": { "keyCode": 63, "modifiers": [] },
  "modelSize": "base.en",
  "language": "en",
  "spokenPunctuation": false,
  "maxRecordings": 0
}
```

Then restart RuWispr from the menu bar.

| Option | Default | Values |
|---|---|---|
| **hotkey** | `63` | Globe (`63`), Right Option (`61`), F5 (`96`), or any key code |
| **modifiers** | `[]` | `"cmd"`, `"ctrl"`, `"shift"`, `"opt"` — combine for chords |
| **modelSize** | `"base.en"` | See model table below |
| **language** | `"en"` | Any [ISO 639-1 code](https://en.wikipedia.org/wiki/List_of_ISO_639-1_codes) — e.g. `it`, `fr`, `de`, `es` |
| **spokenPunctuation** | `false` | Say "comma", "period", etc. to insert punctuation instead of auto-punctuation |
| **maxRecordings** | `0` | Optionally store past recordings locally as `.wav` files for re-transcribing from the tray menu. `0` = nothing stored (default). Set 1-100 to keep that many recent recordings. |

### Models

Larger models are more accurate but slower and use more memory. The default `base.en` is a good balance for most users.

| Model | Size | Speed | Accuracy | Best for |
|---|---|---|---|---|
| `tiny.en` | 75 MB | Fastest | Lower | Quick notes, short phrases |
| **`base.en`** | 142 MB | **Fast** | **Good** | **Most users (default)** |
| `small.en` | 466 MB | Moderate | Better | Longer dictation, technical terms |
| `medium.en` | 1.5 GB | Slower | Great | Maximum accuracy, complex speech |
| `large` | 3 GB | Slowest | Best | Multilingual, highest accuracy (M1 Pro+ recommended) |

> **Non-English languages:** Models ending in `.en` are English-only. To use another language, switch to the equivalent model without the `.en` suffix (e.g. `base.en` → `base`) and set the `language` field to your language code. Multilingual models are slightly less accurate for English but support 99 languages.

If the Globe key opens the emoji picker: **System Settings → Keyboard → "Press 🌐 key to" → "Do Nothing"**

## Menu bar

Click the waveform icon for status and options. **Recent Recordings** lists your last recordings; click one to re-transcribe and copy the result to the clipboard.

| State | Icon |
|---|---|
| Idle | Waveform outline |
| Recording | Bouncing waveform |
| Transcribing | Wave dots |
| Downloading model | Animated download arrow |
| Waiting for permission | Lock |

Click the menu bar icon to access **Copy Last Dictation** — recovers your most recent transcription if you dictated without a text field focused.

## Compare

| | RuWispr | VoiceInk | Wispr Flow | Superwhisper | Apple Dictation |
|---|---|---|---|---|---|
| **Price** | **Free** | $39.99 | $15/mo | $8.49/mo | Free |
| **Open source** | MIT | GPLv3 | No | No | No |
| **100% on-device** | Yes | Yes | No | Yes | Partial |
| **Push-to-talk** | Yes | Yes | Yes | Yes | No |
| **AI features** | No | AI assistant | AI rewriting | AI formatting | No |
| **Account required** | No | No | Yes | Yes | Apple ID |

## Privacy

RuWispr is completely local. Audio is recorded to a temp file, transcribed by whisper.cpp or GigaAM on your CPU/GPU, and the temp file is deleted. No network requests are made except to download models on first run. Optionally, you can configure RuWispr to store a number of past recordings locally via the `maxRecordings` setting. Those recordings stay private and on your machine, and we default to not storing anything.

## Build from source

```bash
git clone https://github.com/ABorovenskoy/ru-wispr.git
cd ru-wispr
brew install whisper-cpp
swift build -c release
.build/release/open-wispr start
```

## Support

RuWispr is free and always will be.

## License

MIT
