# How Vibe Read works

Vibe Read is a local-first macOS app with three focused workflows: dictation,
read-aloud, and configurable text actions.

## Dictation

1. A global shortcut starts a microphone recording.
2. When recording stops, Vibe Read sends that audio directly from the Mac to
   the OpenAI-compatible endpoint configured in Settings.
3. The provider returns text. Vibe Read saves the transcript to a local SQLite
   database and can paste it into the focused app through macOS Accessibility.
4. The retained recording is stored under Application Support. Recordings are
   deleted after seven days by default; the retention period is configurable.
   Transcript text remains until the user deletes it.

There is no Vibe Read server between the app and the configured provider.

## Read-aloud

Read-aloud uses `AVSpeechSynthesizer` and voices installed in macOS. Text entered
in the Read view or captured from another app stays on the Mac and is not sent
to the configured AI provider.

## Text actions

The action palette opens over selected text (Cmd+E by default). Local actions
such as Copy and Read aloud do not make network requests. User-editable rewrite
actions send the action prompt and selected text directly to the configured
OpenAI-compatible provider, then paste its response into the focused app.

Action definitions and shortcuts are stored in macOS preferences. Selected
text is not added to dictation history.

## Storage and network boundary

```text
Microphone ──audio──> configured provider ──text──> local SQLite
Selected text ──────> configured provider ──text──> focused Mac app
Text to read ───────> macOS speech synthesizer
```

The current app has no account system, subscriptions, analytics, cloud
database, cloud storage, or sync. See [PRIVACY.md](PRIVACY.md) and
[LOCAL_DATA.md](LOCAL_DATA.md) for the precise data boundary.

## Permissions

- **Microphone** is required for dictation.
- **Accessibility** is required for global shortcuts, reading selected text,
  and pasting generated text into other apps.

The Read view can still speak text pasted into the app without Accessibility
permission.
