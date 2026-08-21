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
- Keeps normal Fn dictation fast with direct speech-to-text and no text model
- Turns spoken instructions into finished text with the separate Smart Dictation shortcut
- Reads selected text, saved pages, and notes with a searchable ElevenLabs voice browser or macOS voices
- Opens configurable text actions with Cmd + E
- Lets you add, edit, and delete custom Cmd + E actions in the app
- Saves selected text, articles, Wikipedia pages, and YouTube links in a local Library
- Keeps transcript history in a local SQLite database
- Retains local audio for retry and removes it after seven days by default
- Lets every global shortcut be rebound
- Connects directly to ElevenLabs, Groq, OpenRouter, OpenAI, or a custom compatible endpoint
- Configures dictation separately from Smart Dictation and Cmd + E
- Lets you choose the dictation language, a curated model, or a custom model ID where supported

Vibe Read has no account system or operated server in the request path. The source is available under the [MIT License](LICENSE).

## Use Vibe Read

Once the app is installed, setup takes about a minute.

1. Open Vibe Read.
2. In **Providers**, leave **ElevenLabs** selected. Paste your existing key, or choose **Use Existing Key > Use .env File** and select a file containing `ELEVENLABS_API_KEY`.
3. If you pasted the key, click **Save Key**. Then close Settings.
4. The first time macOS asks, allow **Microphone** and **Accessibility** access for Vibe Read.
5. Press **Fn** once to start dictating. Press **Fn** again to stop, transcribe, and paste.

That is all you need for normal dictation. Normal Fn dictation sends audio only
to the chosen dictation provider and pastes the returned transcript. It never
invokes a text model.

The app containing your cursor when you press Send becomes the paste
destination. Vibe Read checks that the same app is still active before posting
Cmd + V, then restores whatever was already on your clipboard. If Vibe Read
knows the paste failed, it copies automatically only when the clipboard is
empty. When the clipboard already contains something, a small prompt lets you
press Return to replace it or Escape to keep it. The dictation remains in local
History either way.

Smart Dictation and provider-backed Cmd + E actions are optional. Configure a
text provider such as Groq, OpenRouter, OpenAI, or a compatible local service,
then press **Fn + Option** once to start Smart Dictation and again to finish.

You do not need to create a new key for each build. With **Use .env File**, Vibe Read remembers the selected file path and reads only `ELEVENLABS_API_KEY` when you dictate. It does not copy that key into Keychain. You can also paste the existing key into Keychain or explicitly recover a key from the previous Vibe Read build. Recovery never displays a macOS password prompt.

Vibe Read never needs your Mac login password. If an older source build shows a password dialog for an old Vibe Read Keychain item, deny it and install the latest build.

## Build from source

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

6. Keep that team and bundle identifier stable so macOS keeps the app's permissions.

7. Build and run.

8. Vibe Read does not show system permission prompts at startup. Click Grant
   Access in Settings or intentionally use a feature that needs access. macOS
   then requests Microphone access for dictation or Accessibility access for
   function-key shortcuts, selected text, and pasting.

9. Follow the five steps in **Use Vibe Read** above.

Read-aloud can use ElevenLabs with the same key used for Scribe dictation, or
voices already on your Mac with no network request. ElevenLabs voices load only
when you choose **Load Voices**. You can search the loaded list and preview a
voice before using it. Ordinary global chords such as Cmd + E use a native
macOS hotkey and do not require Accessibility permission. Smart Dictation and
provider-backed Cmd + E actions are optional.

If you hand this repository to Codex or another coding agent, ask it to build the `Vibe Read` scheme for `My Mac`, install the app, and leave the Providers screen open. Paste your key yourself. Keys should never be placed in source files, chat, or shell history.

## Configure a provider

Open Settings and choose Providers.

Dictation and text processing have separate provider and model choices. Normal
Fn dictation uses only the dictation provider. Smart Dictation and
provider-backed Cmd + E actions use the text provider. A configured Groq,
OpenRouter, or OpenAI key is reused if both sides select that provider.
ElevenLabs powers dictation and optional read-aloud. Custom dictation and
custom text processing have separate URLs and credentials.

Launching Vibe Read and opening Settings do not read Keychain or a selected
`.env` file. Vibe Read reads a provider credential only after you explicitly
verify it or intentionally use a provider-backed feature. A key loaded from Keychain is
cached in memory until you quit the app, so later requests to that provider in
the same run do not read it again.

Older builds used one generic provider key. Vibe Read does not automatically
discover or migrate that key. Re-enter it for the provider you want to use and
use the save action shown for that provider.

Dictation language can stay on Auto detect or use one of 52 explicit ISO language hints, including Russian. ElevenLabs uses Scribe v2. Other dictation providers offer presets plus a custom model ID field.

| Provider | Dictation choices | Smart Dictation and Cmd + E choices | Good fit |
| --- | --- | --- | --- |
| ElevenLabs | Scribe v2 | Not used | Dictation and optional ElevenLabs read-aloud |
| Groq | Whisper Large V3 Turbo or Whisper Large V3 | GPT OSS 120B or 20B | Speed and cost option |
| OpenRouter | GPT-4o Transcribe or Mini | GPT-5.6 Luna, GPT OSS, or a custom model | One key across many models |
| OpenAI | GPT Transcribe, Mini, or Whisper 1 | GPT-5.6 Luna or a custom model | Direct OpenAI access |
| Custom | Any compatible transcription model | Any compatible chat model | Local loopback or another service |

The simplest setup for an existing ElevenLabs user is Scribe v2 for dictation.
Normal Fn dictation needs nothing else. Smart Dictation and provider-backed
Cmd + E actions become available after you add a text provider. Within Groq,
Whisper Large V3 Turbo is the faster dictation preset.

For Groq, OpenRouter, OpenAI, and custom providers, Save & Verify checks the credential and endpoint without uploading audio or selected text. When an applicable model list is available, it also checks the selected model ID. ElevenLabs uses Save Key without a network request because its general model catalog is not an authoritative Scribe check. Your first dictation is the end-to-end ElevenLabs test.

Local Cmd + E actions such as Copy and Read aloud do not need a text provider.
Provider-backed actions return a preview. Vibe Read applies the result only
after you choose Apply and only to the app where the action began. Add, edit,
or delete custom actions from the Actions screen. Action names and prompts stay
in macOS preferences. On upgrade, Vibe Read removes exact duplicate custom
actions created by older versions while preserving the first copy and its
position.

Smart Dictation is a separate path. It sends audio to the chosen dictation
provider, then sends the raw transcript, your locally stored Smart Dictation
prompt, and a sanitized name of the app where dictation began to the text
provider. It does not send selected text, window contents, screenshots, or
documents. If the text edit fails, Vibe Read pastes or saves the raw transcript
instead.

Cmd + E also understands a copied or selected web address. It can read or save ordinary articles and Wikipedia pages without browser automation. For YouTube, it uses public captions when the video exposes them and otherwise saves the link. Saved items live in the local Library and can be read, summarized, copied, reopened, or deleted.

Vibe Read talks to these provider routes directly.

| Provider | Method | Route | Used for |
| --- | --- | --- | --- |
| ElevenLabs | `POST` | `/v1/speech-to-text` | Dictation audio |
| ElevenLabs | `GET` | `/v2/voices` | Voice picker, only when requested |
| ElevenLabs | `POST` | `/v1/text-to-speech/{voice_id}` | Optional read-aloud |
| Groq, OpenRouter, OpenAI, or custom | `GET` | `/models` | Connection and model check |
| Groq, OpenRouter, OpenAI, or custom | `POST` | `/audio/transcriptions` | Dictation audio |
| Groq, OpenRouter, OpenAI, or custom | `POST` | `/chat/completions` | Smart Dictation and configurable text actions |

Remote providers must use HTTPS. Plain HTTP is accepted only for `localhost`, `127.0.0.1`, or `::1`.

## Default shortcuts

| Action | Default shortcut |
| --- | --- |
| Hands-free dictation | `fn` |
| Push-to-talk dictation | `fn + Space` |
| Dictate, then open actions | `fn + Control` |
| Smart Dictation | `fn + Option` |
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
| Provider API keys | A `.env` file you choose, or macOS Keychain when you paste or recover a key. Groq, OpenRouter, and OpenAI can be shared between compatible features. ElevenLabs can power dictation and read-aloud. Custom dictation and custom text remain separate. |
| Dictation audio | Your configured provider when you transcribe |
| Text used by an action | Your configured text provider when you run that action |
| Smart Dictation text | Your configured text provider only when you use Smart Dictation. The request contains the raw transcript, your local Smart prompt, and a sanitized original app name. |
| Completed auto-paste text | Temporarily staged on the local clipboard for Cmd + V, then the previous clipboard is restored. A known fallback replaces an occupied clipboard only after confirmation. |
| Saved Library items | Local JSON until you delete them |
| ElevenLabs voice list | Voice metadata is fetched only when you choose Load Voices and may be cached in macOS preferences |
| Read-aloud or preview text | ElevenLabs only when selected, otherwise the macOS speech synthesizer. Preview and read requests use your provider credits. |

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
