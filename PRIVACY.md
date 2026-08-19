# Privacy

Vibe Read is local-first, but dictation and optional text transformations are
not offline unless the user configures a compatible service on the Mac. This
document describes the current app's data flow.

## Stored on the Mac

- Transcript history is stored in a SQLite database under the user's
  Application Support directory and remains until the user deletes it. Each
  successful row stores the provider transcript and the final text used by the
  app. They are identical unless a custom cleanup prompt changes the text.
- Dictation recordings are stored beside that database and deleted after seven
  days by default. The user can choose immediate, one-day, seven-day, 30-day,
  or indefinite retention.
- Shortcuts, provider choices, provider URL and model identifiers, dictation
  language, vocabulary, retention choice, and user-defined action prompts are
  stored in macOS preferences.
- API keys are stored in macOS Keychain. Groq, OpenRouter, and OpenAI each use
  one provider item that can power dictation and Cmd + E. ElevenLabs uses a
  dictation-only item. Custom dictation and custom text actions use separate
  Keychain items.

Launching Vibe Read and opening Settings do not read Keychain. The app reads a
saved provider key only after the user explicitly verifies it or intentionally
uses that provider. A loaded key is cached in memory until the
app quits. Older generic provider keys are not automatically discovered or
migrated. Users must re-enter them for the provider they want to use.

The database and recordings are not application-level encrypted. macOS account
security restricts access, and users can enable FileVault for encryption at
rest.

## Sent over the network

Vibe Read contacts a configured provider when the user starts dictation, runs
a provider-backed text action, uses a custom dictation cleanup mode, or asks
the app to verify provider access.

### Dictation

Recorded audio goes directly from the Mac to the selected dictation provider:

- ElevenLabs dictation sends recorded audio to
  `https://api.elevenlabs.io/v1/speech-to-text` with the Scribe v2 model.
- Groq dictation sends recorded audio to Groq's OpenAI-compatible
  `/audio/transcriptions` endpoint.
- OpenRouter dictation sends recorded audio to OpenRouter's
  `/audio/transcriptions` endpoint. OpenRouter can route the request to an
  upstream model provider.
- OpenAI dictation sends recorded audio to OpenAI's
  `/audio/transcriptions` endpoint.
- Custom dictation sends recorded audio to `/audio/transcriptions` under the
  endpoint configured by the user.

These requests include the selected model where applicable and may include an
explicit language. Vocabulary can also be included for providers that support
the app's prompt field. The raw transcript returned by the provider is stored
locally.

### Text processing

A custom dictation cleanup prompt sends the raw transcript, the prompt, and the
selected text model to the separately configured text provider. If cleanup
fails, Vibe Read keeps and uses the raw transcript instead of discarding a
successful dictation.

A provider-backed Cmd + E action sends the selected text, action prompt, and
selected model to the text provider configured for Cmd + E. Its response
appears in the action palette for review. The user can copy, discard, or apply
it explicitly.

Text providers are OpenRouter, Groq, OpenAI, or a custom OpenAI-compatible
endpoint. These requests use the provider's `/chat/completions` endpoint.

### Verification

For Groq, OpenRouter, OpenAI, and custom providers, **Save and Verify** sends an
authenticated request to a provider model-list endpoint. It does not upload
dictation audio, selected text, or an action prompt. A successful verification
checks access to that endpoint. It does not guarantee that every selected model
is available to the account. ElevenLabs uses **Save Key** without a network
request. Its first dictation is the Scribe v2 end-to-end test.

These calls go directly from the Mac to that endpoint. The provider may log,
retain, or use submitted data according to its own policy. Users should choose
a provider and models appropriate for the sensitivity of their material. When
an aggregator routes to another company, users should review the policies and
settings of both services.

ElevenLabs enables request logging by default for standard API usage. Its zero
retention mode is a provider-side enterprise feature. Vibe Read does not claim
or enable provider-side zero retention. Review the provider settings and policy
that apply to your account.

The app's provider client disables URL caching and cookies for these requests.
This does not control what a provider retains after receiving a request.

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

Vibe Read does not show system permission prompts at startup. macOS access is
requested only after the user clicks Grant Access or intentionally uses a
feature that needs it.

- **Microphone:** records audio only after the user starts dictation.
- **Accessibility:** observes function-key shortcuts, reads selected text, and
  inserts text into other applications. Ordinary global chords such as Cmd + E
  do not require this permission.
- **Clipboard:** is used for explicit copy actions and can be offered as a
  fallback when Accessibility cannot read the current selection.

Selected text used by an action is held in memory for the operation and is not
added to dictation history.

## Control and deletion

Users can delete individual dictations, all retained audio, or all history and
audio from the app. Provider keys can be removed separately in AI Provider
settings. See [LOCAL_DATA.md](LOCAL_DATA.md) for paths, backup instructions,
and complete removal steps. A generic provider item created by an older build
is never automatically discovered or removed and may need to be deleted
manually in Keychain Access.

Removing local data does not delete information already submitted to a chosen
provider. Use that provider's controls for its copies.
