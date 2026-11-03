# OpenWhisper

A tiny, open-source dictation app for macOS. Press a shortcut, talk, press it again — your words are transcribed by OpenAI and pasted wherever your cursor is.

- **Private by design** — audio goes straight from your Mac to `api.openai.com`. No other servers, no analytics, no accounts. Your API key stays in your keychain.
- **Minimal** — a menu-bar icon, a little pill above the Dock while you talk, and a settings window. ~900 lines of Swift, no dependencies.
- **Always there** — runs in the background and starts at login.

## Install

Requires macOS 13+ and the Xcode Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/<you>/openwhisper.git
cd openwhisper
./scripts/install.sh
```

This builds the app, installs it to `/Applications`, launches it, and registers it as a login item. On first launch:

1. Paste your [OpenAI API key](https://platform.openai.com/api-keys) into Settings.
2. Press **⌃⌥Space**, allow microphone access, and speak.
3. Press **⌃⌥Space** again. When asked, allow **Accessibility** — that's what lets OpenWhisper press ⌘V for you.

Re-run `./scripts/install.sh` any time to update.

## Use

| | |
|---|---|
| **⌃⌥Space** (configurable) | Start recording / stop and transcribe |
| **Esc** | Cancel while recording or transcribing |
| Menu-bar waveform | Start dictation, Settings, Quit |

The transcript is always left on your clipboard, so if it didn't paste where you wanted, just ⌘V.

Settings: API key, shortcut, model (`gpt-transcribe` by default; also `gpt-4o-transcribe`, `gpt-4o-mini-transcribe`, `whisper-1`), and launch at login.

## How it works

| File | |
|---|---|
| `HotKey.swift` | Global shortcut via Carbon `RegisterEventHotKey` |
| `Recorder.swift` | `AVAudioRecorder` → 16 kHz mono AAC, with level metering |
| `Transcriber.swift` | One multipart `POST /v1/audio/transcriptions` |
| `Paster.swift` | Clipboard + synthesized ⌘V |
| `Overlay.swift` | The non-activating floating pill |
| `SettingsView.swift` | SwiftUI settings window |

### About signing

macOS ties Microphone/Accessibility permissions to an app's code signature. So you only have to grant them once, `install.sh` creates a self-signed certificate called **OpenWhisper Local Signing** in your login keychain and signs every build with it. To use your own identity instead: `CODESIGN_IDENTITY="Apple Development: …" ./scripts/install.sh`.

## Uninstall

```sh
./scripts/uninstall.sh
```

Removes the app, its settings, the stored API key, its permissions, and the local signing certificate.

## License

MIT
