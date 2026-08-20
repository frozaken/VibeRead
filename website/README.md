# Vibe Read website

The static landing page for Vibe Read, a free and open source Mac app for
fast voice dictation, optional Smart Dictation, reading selected text aloud,
and configurable Cmd + E actions.

## App setup

1. Open Vibe Read.
2. Open Providers and paste an ElevenLabs API key, or choose an existing `.env` file.
3. Click Save Key only if you pasted the key.
4. Allow Microphone and Accessibility when macOS asks.
5. Press Fn once to start dictation and Fn again to send.

No Vibe Read account, subscription, database, or server setup is required.
An existing key can stay in a chosen `.env` file. A new key is not required for
each build.

## Static only

This site has no runtime backend.

- No API routes, authentication, accounts, or database
- No analytics, cookies, tracking pixels, or forms
- No billing, subscriptions, or payment integration
- No hosted transcription, speech, or AI proxy
- No environment variables or secret keys

`npm run build` exports plain static files to `out/`. The public website is not
part of the desktop app runtime and can be hosted on any static file host.
When deploying the full repository on Vercel, set the project root directory
to `website`.

```bash
# Requires Node.js 20.9 or newer
npm ci
npm run typecheck
npm run build
```

## Public source

All site calls to action point to the public source repository at
`https://github.com/mathias-heide/VibeRead`.

The canonical production domain is `https://viberead.ai`.

## Privacy

Vibe Read stores history and preferences locally. Retained audio is removed
after seven days by default, and **Immediately** removes successful and failed
recordings as soon as their result is recorded.

The desktop app connects directly to the providers configured by the user.
Dictation can use ElevenLabs, Groq, OpenRouter, OpenAI, or a custom
OpenAI-compatible endpoint. Normal Fn dictation never invokes the text
provider. Smart Dictation and provider-backed Cmd + E actions can use a
separate OpenRouter, Groq, OpenAI, or custom provider. Remote providers receive
audio or text only when the user asks them to process it, and each provider
applies its own terms and retention policy.

Smart Dictation sends the raw transcript, the local Smart prompt, and a
sanitized original app name to the text provider. It does not send selected
text, window titles, screenshots, or document contents. If the edit fails, the
raw transcript is preserved.

Provider keys can stay in a chosen `.env` file or be stored in macOS Keychain. Groq, OpenRouter, and OpenAI can
each use one key across dictation, Smart Dictation, and Cmd + E. ElevenLabs
can power dictation and optional read-aloud.
Custom dictation and custom text use separate keys and endpoint URLs. Keys are
never part of this static website. Users can also configure a compatible
service running on their Mac.

Launching Vibe Read and opening Settings do not read Keychain or a selected
`.env` file. The app reads a credential only after explicit verification or
intentional provider use. Keychain values are cached in memory until the app quits. Generic keys from older builds are not
automatically discovered or migrated. Users must re-enter them for the provider
they want to use.

Vibe Read does not show system permission prompts at startup. macOS access is
requested only after the user clicks Grant Access or intentionally uses a
feature that needs it.

ElevenLabs voices load only after an explicit action. Voice metadata may be
cached locally. Preview and read-aloud send the entered text to ElevenLabs and
use the user's provider credits. Custom Cmd + E actions can be added, edited,
or deleted in the app. Exact duplicates left by older builds are repaired on
load.
