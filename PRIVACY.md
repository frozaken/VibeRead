# Privacy

Vibe Read is local-first, but dictation and optional text transformations are
not necessarily offline. This document describes the current app's data flow.

## Stored on the Mac

- Transcript history is stored in a SQLite database under the user's
  Application Support directory and remains until the user deletes it.
- Dictation recordings are stored beside that database and deleted after seven
  days by default. The user can choose immediate, one-day, seven-day, 30-day,
  or indefinite retention.
- Shortcuts, provider URL and model names, vocabulary, retention choice, and
  user-defined action prompts are stored in macOS preferences.
- The provider API key is stored in macOS Keychain.

The database and recordings are not application-level encrypted. Normal macOS
account security and FileVault protect data at rest.

## Sent over the network

Vibe Read contacts only the OpenAI-compatible endpoint configured by the user:

- Dictation sends the recorded audio, selected transcription model, and an
  optional vocabulary prompt to `/audio/transcriptions`.
- A user-triggered rewrite action sends the selected text, action prompt, and
  selected text model to `/chat/completions`.
- **Test Connection** sends a request to `/models`.

These calls go directly from the Mac to that endpoint. The provider may log,
retain, or use submitted data according to its own policy. Users should choose
a provider and models appropriate for the sensitivity of their material.

Read-aloud uses the macOS speech synthesizer locally. Copying, pasting, opening
the action palette, and editing action definitions do not by themselves send a
network request.

## Not included

The current app includes no:

- Vibe Read account or authentication
- Vibe Read cloud database, storage, or sync
- subscription or payment flow
- product analytics or tracking SDK
- automatic crash-reporting service
- operated API proxy or relay
- hosted auto-update service

In particular, the local-only application does not use Supabase, PostHog, or
Stripe.

## Permissions

- **Microphone:** records audio only after the user starts dictation.
- **Accessibility:** observes configured global shortcuts, reads selected text,
  and pastes text into the active application.
- **Clipboard:** may be used as a fallback to obtain selected text and for
  explicit copy/paste actions.

Selected text used by an action is held in memory for the operation and is not
added to dictation history.

## Control and deletion

Users can delete individual dictations, all retained audio, or all history and
audio from the app. The API key can be removed separately in AI Provider
settings. See [LOCAL_DATA.md](LOCAL_DATA.md) for paths, backup instructions, and
complete removal steps.

Removing local data does not delete information already submitted to a chosen
provider. Use that provider's controls for its copies.
