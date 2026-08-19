# How Vibe Read works

Vibe Read is a local-first macOS app for dictation, read-aloud, and
configurable text actions. Local-first describes storage, not speech
processing. Unless a compatible service is running on the Mac, dictation audio
leaves the Mac for the provider selected by the user.

## Provider setup

Dictation and Cmd + E are configured independently.

| Feature | Built-in choices | What can be selected |
| --- | --- | --- |
| Dictation | ElevenLabs, Groq, OpenRouter, OpenAI, Custom OpenAI-compatible | Provider, transcription model where supported, and language or auto detect |
| Cmd + E and custom dictation cleanup | OpenRouter, Groq, OpenAI, Custom OpenAI-compatible | Provider and text model |

Vibe Read stores one API key for each built-in provider in macOS Keychain. If
Groq, OpenRouter, or OpenAI is selected for both dictation and Cmd + E, both
features use that provider's saved key. ElevenLabs can power both Scribe
dictation and optional ElevenLabs read-aloud. Custom
dictation and custom text actions have separate endpoint URLs and Keychain
items. Provider choices, model identifiers, language, and custom endpoint URLs
are non-secret preferences stored by macOS.

Launching Vibe Read and opening Settings do not read Keychain. The app reads a
saved key only after the user explicitly verifies it or intentionally uses that
provider for dictation, cleanup, or a text action. After a key is loaded,
the app caches it in memory until the app quits. Older generic provider keys
are not automatically discovered or migrated. Users must re-enter an older key
for the provider they want to use and choose its explicit save action.

A remote custom endpoint must use HTTPS. An HTTP endpoint is accepted only for
loopback addresses such as `127.0.0.1` or `localhost`. A loopback service may be
configured without an API key.

## Dictation

1. A global shortcut starts a microphone recording.
2. When recording stops, Vibe Read sends that audio directly from the Mac to
   the dictation provider selected in Settings.
3. The provider returns a raw transcript.
4. The default dictation mode uses that transcript as-is. If the active mode
   has a custom cleanup prompt, Vibe Read sends the raw transcript and prompt
   to the separately configured text provider.
5. If cleanup succeeds, its response becomes the final text. If cleanup fails,
   Vibe Read keeps the successful raw transcript as the final text and reports
   a nonfatal warning.
6. Vibe Read saves the raw transcript and final text to a local SQLite
   database. It can insert the final text into another app through macOS
   Accessibility.
7. The retained recording is stored under Application Support. Audio is
   deleted after seven days by default. Transcript text remains until the user
   deletes it.

There is no Vibe Read server, account, or cloud database between the app and
the configured providers.

## Read-aloud

Read-aloud has two explicit modes. The macOS mode uses `AVSpeechSynthesizer`
and keeps text on the Mac. The ElevenLabs mode sends only the text the user
chooses to read directly to ElevenLabs, downloads generated audio, and plays it
locally. Voice loading, preview, and reading are explicit actions and are the
only times read-aloud accesses the saved ElevenLabs key.

## Text actions

The action palette opens over selected text with Cmd + E by default. Local
actions such as Copy and Read aloud do not make network requests. User-editable
rewrite actions send the action prompt and selected text directly to the text
provider configured for Cmd + E. The result stays in the palette for review.
The user can copy it, cancel it, or explicitly apply it. The text provider is
optional, so local actions remain available without one.

Action definitions and shortcuts are stored in macOS preferences. Selected
text is not added to dictation history.

When the current selection or clipboard contains a web address, Cmd + E can
extract a readable article or Wikipedia page, or use public YouTube captions.
It does not automate the browser or request Apple Events access. Save to
Library writes the extracted text or link to `library.json` under the local
Application Support directory.

## Storage and network boundary

```text
Microphone -> selected dictation provider -> raw transcript -> local SQLite
                                                     |
                                                     +-> optional cleanup
                                                         text provider

Selected text -> optional Cmd + E text provider -> preview -> explicit apply
Text to read  -> macOS speech synthesizer or chosen ElevenLabs voice
Copied URL    -> direct page fetch -> local Library
```

The current app has no account system, subscriptions, analytics, cloud
database, cloud storage, or sync. See [PRIVACY.md](PRIVACY.md) and
[LOCAL_DATA.md](LOCAL_DATA.md) for the precise data boundary.

## Permissions

Vibe Read does not request system access at startup. A macOS permission prompt
appears only after the user clicks Grant Access or intentionally uses a feature
that needs the permission.

- **Microphone** is required for dictation.
- **Accessibility** is required for function-key shortcuts, reading selected
  text, and inserting text into other apps. Ordinary global chords such as
  Cmd + E do not require it.
- **Clipboard** access is used by explicit copy actions and can be offered as a
  fallback when an app does not expose selected text through Accessibility.

The Read view can still speak text pasted into the app without Accessibility
permission.
