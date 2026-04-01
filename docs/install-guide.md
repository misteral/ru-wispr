# Installation Guide

## Quick Install

1. Download the latest DMG from [GitHub Releases](https://github.com/misteral/dikto/releases/latest)
2. Open the DMG
3. Drag `Dikto.app` to **Applications**
4. Launch **Dikto** from Applications or Spotlight

A waveform icon appears in your menu bar when it's running.

## What happens on first launch

1. **Requests permissions** — Microphone and Accessibility
2. **Creates config** in iCloud Drive
3. **Downloads the selected model** on first use if it's not already present
4. **Starts in the menu bar** and waits for your hotkey

## Granting Permissions

Dikto needs two macOS permissions to work:

### Microphone

A system dialog will appear automatically. Click **Allow**.

### Accessibility

Accessibility permission lets Dikto detect your hotkey globally. During first launch, a pop-up like this will appear:

<p align="center">
  <img width="465" alt="Accessibility permission prompt" src="https://github.com/user-attachments/assets/9a0533ae-c174-4395-9533-46b55c3cb592" />
</p>

Click it to jump directly to the Accessibility settings. Find **Dikto** in the list and toggle it **ON**:

<p align="center">
  <img width="711" alt="Accessibility settings with Dikto toggled on" src="https://github.com/user-attachments/assets/f8243e28-4fae-4aba-a030-5c4c66c3cf07" />
</p>

If you missed the pop-up, navigate there manually:

> **System Settings → Privacy & Security → Accessibility**

If `Dikto` doesn't appear in the list, click the **+** button and add it from `/Applications/Dikto.app`.

### Non-English macOS

The permission steps are the same regardless of your system language. macOS translates the Settings UI automatically — only the app name **Dikto** stays the same.

For reference, here's the path in a few languages:

| Language | Path |
|---|---|
| English | System Settings → Privacy & Security → Accessibility |
| Italian | Impostazioni di Sistema → Privacy e sicurezza → Accessibilità |
| French | Réglages du système → Confidentialité et sécurité → Accessibilité |
| German | Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen |
| Spanish | Ajustes del Sistema → Privacidad y seguridad → Accesibilidad |
| Portuguese | Ajustes do Sistema → Privacidade e Segurança → Acessibilidade |

## Troubleshooting

### App not appearing in Accessibility list

1. Open **System Settings → Privacy & Security → Accessibility**
2. Click the **+** button
3. Navigate to `/Applications/` and select `Dikto.app`
4. Toggle it **ON**
5. Quit and relaunch Dikto

### Microphone denied

If you accidentally denied microphone access:

1. Go to **System Settings → Privacy & Security → Microphone**
2. Find **Dikto** and toggle it **ON**
3. Quit and relaunch Dikto

### Globe key opens emoji picker

If the Globe key (🌐) triggers the emoji picker instead of Dikto:

> **System Settings → Keyboard → "Press 🌐 key to" → "Do Nothing"**

### Right Option hotkey also triggers from left Option

If you set right Option (`keyCode: 61`) as the hotkey, Dikto should only trigger from the physical right Option key. If left Option also triggers, update to the latest build.

### Config resets to default after editing `config.json`

If `config.json` has invalid JSON or unsupported values, Dikto prints a warning and falls back to defaults for that run, without overwriting your file. Fix the JSON, then quit Dikto from the menu bar and launch it again.

## Language Support

Dikto supports Whisper multilingual models. To dictate in a different language, edit `~/Library/Mobile Documents/com~apple~CloudDocs/Dikto/config.json`:

1. Switch to a **multilingual model** (remove the `.en` suffix)
2. Set the **language** to your [ISO 639-1 code](https://en.wikipedia.org/wiki/List_of_ISO_639-1_codes)

For example, to use Italian:

```json
{
  "language": "it",
  "modelSize": "base"
}
```

Then quit Dikto from the menu bar and launch it again.

The multilingual model will be downloaded automatically on next use.

### Available models

| Model | English-only | Multilingual | Size |
|---|---|---|---|
| tiny | `tiny.en` | `tiny` | ~75 MB |
| base | `base.en` | `base` | ~142 MB |
| small | `small.en` | `small` | ~466 MB |
| medium | `medium.en` | `medium` | ~1.5 GB |

Larger models are more accurate but slower. `base` is a good starting point for most languages.

### Common language codes

| Language | Code |
|---|---|
| English | `en` |
| Italian | `it` |
| French | `fr` |
| German | `de` |
| Spanish | `es` |
| Portuguese | `pt` |
| Japanese | `ja` |
| Chinese | `zh` |
| Korean | `ko` |

## Uninstall

1. Quit Dikto from the menu bar
2. Move `Dikto.app` from **Applications** to the Trash
3. Optionally remove app data for a full reset:
   - `~/Library/Mobile Documents/com~apple~CloudDocs/Dikto`
   - `~/Library/Application Support/Dikto`

If you're working from a local checkout of the repo, you can also run `bash scripts/uninstall.sh` for a full cleanup.

## Build from Source

```bash
git clone https://github.com/misteral/dikto.git
cd dikto
brew install whisper-cpp
swift build -c release
.build/release/dikto start
```
