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
- Connects directly to the OpenAI-compatible provider you choose

Vibe Read has no account or operated server in the request path. The source is available under the [MIT License](LICENSE).

## Quick start

You need macOS 13 Ventura or later and Xcode 16 or later. The project has no third-party Swift package dependencies.

1. Clone the repository.

   ```bash
   git clone https://github.com/mathias-heide/VibeRead.git
   cd VibeRead
   ```

2. Open `Vibe Read.xcodeproj` in Xcode.

3. Select the `Vibe Read` scheme and `My Mac`.

4. Choose a local signing identity if Xcode asks.

5. Build and run.

6. Grant Microphone access for dictation and Accessibility access for global shortcuts, selected text, and pasting.

7. Open Settings and configure your AI provider.

Read-aloud works with the voices already on your Mac. Dictation and provider-backed text actions need an OpenAI-compatible endpoint.

## Configure a provider

Open Settings and choose AI Provider. Add the base URL, API key, transcription model, and text-action model for your provider. An API key is optional for a loopback service that accepts unauthenticated requests.

Vibe Read uses these OpenAI-compatible routes relative to the base URL.

| Method | Route | Used for |
| --- | --- | --- |
| `GET` | `/models` | Connection test |
| `POST` | `/audio/transcriptions` | Dictation audio |
| `POST` | `/chat/completions` | Configurable text actions |

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

Change any shortcut under Settings and Shortcuts. Global shortcuts require Accessibility permission and may conflict with shortcuts owned by macOS or another app.

## Privacy

Vibe Read stores its own data on your Mac. Provider requests go directly from the app to the endpoint configured in Settings.

| Data | Where it goes |
| --- | --- |
| Transcript history | Local SQLite until you delete it |
| Audio kept for retry | Local files removed after seven days by default |
| API key | macOS Keychain |
| Dictation audio | Your configured provider when you transcribe |
| Text used by an action | Your configured provider when you run that action |
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
- [Contributing](CONTRIBUTING.md)
- [Static website](website/README.md)

## Contributing

Bug fixes, focused improvements, and documentation updates are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

For security reports, follow [SECURITY.md](SECURITY.md).

## License

Vibe Read is released under the [MIT License](LICENSE).
