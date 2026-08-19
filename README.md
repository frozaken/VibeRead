<p align="center">
  <img src="Vibe%20Read/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="128" alt="Vibe Read app icon">
</p>

<h1 align="center">Vibe Read</h1>

<p align="center">
  Stop typing, start talking.
</p>

<p align="center">
  Free and open source Mac dictation, read-aloud, and configurable Cmd + E actions.
</p>

<p align="center">
  <a href="https://github.com/mathias-heide/VibeRead/actions/workflows/ci.yml"><img src="https://github.com/mathias-heide/VibeRead/actions/workflows/ci.yml/badge.svg" alt="CI status"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-0A0A0A?logo=apple&logoColor=white" alt="macOS 13 or later">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-00332C" alt="MIT License"></a>
</p>

<p align="center">
  <a href="https://viberead.ai">Website</a> ·
  <a href="HOW-IT-WORKS.md">How it works</a> ·
  <a href="PRIVACY.md">Privacy</a> ·
  <a href="CONTRIBUTING.md">Contributing</a>
</p>

> The current local-first version is built from source. A signed local-first download is not published yet.

## What it does

- Dictates into the Mac app you are already using
- Reads selected text aloud with voices built into macOS
- Opens configurable text actions with Cmd + E
- Keeps transcript history in a local SQLite database
- Retains local audio for retry and removes it after seven days by default
- Lets every global shortcut be rebound
- Connects directly to ElevenLabs, Groq, OpenRouter, OpenAI, or a custom compatible endpoint
- Configures dictation and Cmd + E independently
- Lets you choose the dictation language, a curated model, or a custom model ID where supported

Vibe Read has no account system or operated server in the request path. The source is available under the [MIT License](LICENSE).

## Quick start

You need macOS 13 Ventura or later and Xcode 16 or later. The project has no third-party Swift package dependencies.

1. Clone the repository.

   ```bash
   git clone https://github.com/mathias-heide/VibeRead.git
   cd VibeRead
   ```

2. Open `Vibe Read.xcodeproj` in Xcode.

3. Select the `Vibe Read` scheme and `My Mac`.

4. Open the app target under Signing & Capabilities.

5. Choose your Personal Team and give your fork a unique bundle identifier such as `com.yourname.VibeRead`.

6. Keep that team and bundle identifier stable. Changing either one can make macOS ask for permissions again and can create a separate Keychain namespace.

7. Build and run.

8. Vibe Read does not show system permission prompts at startup. Click Grant
   Access in Settings or intentionally use a feature that needs access. macOS
   then requests Microphone access for dictation or Accessibility access for
   function-key shortcuts, selected text, and pasting.

9. The app opens AI Provider settings on a clean install. Pick a dictation provider and enter your own key. ElevenLabs uses Save Key. The other hosted providers use Save & Verify.

Read-aloud works with the voices already on your Mac. Ordinary global chords such as Cmd + E use a native macOS hotkey and do not require Accessibility permission. Provider-backed Cmd + E actions are optional.

If you hand this repository to Codex or another coding agent, ask it to follow the same steps, build the `Vibe Read` scheme for `My Mac`, and leave provider keys for you to enter in the app. Keys should never be placed in source files or shell history.

## Configure a provider

Open Settings and choose AI Provider.

Dictation and Cmd + E have separate provider and model choices. A saved Groq,
OpenRouter, or OpenAI key is reused if both features select that provider.
ElevenLabs is dictation-only. Custom dictation and custom text actions have
separate URLs and Keychain entries.

Launching Vibe Read and opening Settings do not read Keychain. Vibe Read reads
a saved provider key only after you explicitly verify it or intentionally use
a provider-backed feature. A key loaded from Keychain is
cached in memory until you quit the app, so later requests to that provider in
the same run do not read it again.

Older builds used one generic provider key. Vibe Read does not automatically
discover or migrate that key. Re-enter it for the provider you want to use and
use the save action shown for that provider.

Dictation language can stay on Auto detect or be set explicitly. ElevenLabs uses Scribe v2. Other dictation providers offer presets plus a custom model ID field.

| Provider | Dictation choices | Cmd + E choices | Good fit |
| --- | --- | --- | --- |
| ElevenLabs | Scribe v2 | Not used | Setup tested most heavily with Vibe Read |
| Groq | Whisper Large V3 Turbo or Whisper Large V3 | GPT OSS 120B or 20B | Speed and cost option |
| OpenRouter | GPT-4o Transcribe or Mini | GPT-5.6 Luna, GPT OSS, or a custom model | One key across many models |
| OpenAI | GPT Transcribe, Mini, or Whisper 1 | GPT-5.6 Luna or a custom model | Direct OpenAI access |
| Custom | Any compatible transcription model | Any compatible chat model | Local loopback or another service |

The simplest setup for an existing ElevenLabs user is Scribe v2 for dictation. Cmd + E can stay local-only until you add a separate text provider. Within Groq, Whisper Large V3 Turbo is the faster dictation preset.

For Groq, OpenRouter, OpenAI, and custom providers, Save & Verify checks the credential and endpoint without uploading audio or selected text. When an applicable model list is available, it also checks the selected model ID. ElevenLabs uses Save Key without a network request because its general model catalog is not an authoritative Scribe check. Your first dictation is the end-to-end ElevenLabs test.

Local Cmd + E actions such as Copy and Read aloud do not need a text provider. Provider-backed actions return a preview. Vibe Read applies the result only after you choose Apply and only to the app where the action began.

Vibe Read talks to these provider routes directly.

| Provider | Method | Route | Used for |
| --- | --- | --- | --- |
| ElevenLabs | `POST` | `/v1/speech-to-text` | Dictation audio |
| Groq, OpenRouter, OpenAI, or custom | `GET` | `/models` | Connection and model check |
| Groq, OpenRouter, OpenAI, or custom | `POST` | `/audio/transcriptions` | Dictation audio |
| Groq, OpenRouter, OpenAI, or custom | `POST` | `/chat/completions` | Configurable text actions |

Remote providers must use HTTPS. Plain HTTP is accepted only for `localhost`, `127.0.0.1`, or `::1`.

## Default shortcuts

| Action | Default shortcut |
| --- | --- |
| Hands-free dictation | `fn` |
| Push-to-talk dictation | `fn + Space` |
| Dictate, then open actions | `fn + Control` |
| Paste last dictation | `Control + Command + V` |
| Open text actions | `Command + E` |
| Read selected text | `Command + Shift + E` |
| Pause or resume read-aloud | `Command + Shift + Space` |

Change any shortcut under Settings and Shortcuts. Ordinary chords are reserved as native global hotkeys. Function-key shortcuts, selected text, and pasting require Accessibility permission. Settings reports a conflict when macOS or another app already owns a chord.

## Privacy

Vibe Read stores its own data on your Mac. Provider requests go directly from the app to the endpoint configured in Settings.

| Data | Where it goes |
| --- | --- |
| Transcript history | Local SQLite until you delete it |
| Audio kept for retry | Local files removed after seven days by default |
| Provider API keys | macOS Keychain. Groq, OpenRouter, and OpenAI can be shared between features. ElevenLabs is dictation-only. Custom dictation and custom text use separate items. |
| Dictation audio | Your configured provider when you transcribe |
| Text used by an action | Your configured provider when you run that action |
| Transcript cleanup text | Your configured text provider only when a custom cleanup mode is enabled |
| Read-aloud text | The macOS speech synthesizer |

You can change audio retention or clear local data from Settings. A remote provider handles requests under its own privacy and retention terms. Use a compatible loopback service if you want provider requests to remain on your Mac.

Read [Privacy](PRIVACY.md) and [Local data](LOCAL_DATA.md) for the complete data model.

## Local data

Transcripts and retained audio live in this directory.

```text
~/Library/Application Support/VibeRead/
```

Read [LOCAL_DATA.md](LOCAL_DATA.md) before backing up, moving, or deleting data.

## Build and test

Build from Terminal without code signing.

```bash
xcodebuild \
  -project "Vibe Read.xcodeproj" \
  -scheme "Vibe Read" \
  -configuration Debug \
  -destination "platform=macOS" \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Run the unit tests with a disposable data directory and preferences suite.

```bash
xcodebuild \
  -project "Vibe Read.xcodeproj" \
  -scheme "Vibe Read" \
  -destination "platform=macOS" \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:"Vibe ReadTests" \
  test
```

The tests do not migrate or clean your real dictation history.

## Project guide

- [How it works](HOW-IT-WORKS.md)
- [Local data](LOCAL_DATA.md)
- [Privacy](PRIVACY.md)
- [Security](SECURITY.md)
- [Third-party notices](THIRD_PARTY_NOTICES.md)
- [Contributing](CONTRIBUTING.md)
- [Static website](website/README.md)

## Contributing

Bug fixes, focused improvements, and documentation updates are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

For security reports, follow [SECURITY.md](SECURITY.md).

## License

Vibe Read is released under the [MIT License](LICENSE).
