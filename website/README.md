# Vibe Read website

The static landing page for Vibe Read, a free and open source Mac app for
voice dictation, reading selected text aloud, and configurable Cmd + E
actions.

## App setup

1. Open Vibe Read.
2. Open Providers and paste an ElevenLabs API key.
3. Click Save Key.
4. Allow Microphone and Accessibility when macOS asks.
5. Press Fn once to start dictation and Fn again to send.

No Vibe Read account, subscription, database, or server setup is required.

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
OpenAI-compatible endpoint. Cmd + E and custom dictation cleanup can use a
separate OpenRouter, Groq, OpenAI, or custom provider. Remote providers receive
audio or text only when the user asks them to process it, and each provider
applies its own terms and retention policy.

Provider keys are stored in macOS Keychain. Groq, OpenRouter, and OpenAI can
each use one key across dictation and Cmd + E. ElevenLabs is dictation-only.
Custom dictation and custom text use separate keys and endpoint URLs. Keys are
never part of this static website. Users can also configure a compatible
service running on their Mac.

Launching Vibe Read and opening Settings do not read Keychain. The app reads a
saved key only after explicit verification or intentional provider use, then
caches it in memory until the app quits. Generic keys from older builds are not
automatically discovered or migrated. Users must re-enter them for the provider
they want to use.

Vibe Read does not show system permission prompts at startup. macOS access is
requested only after the user clicks Grant Access or intentionally uses a
feature that needs it.
