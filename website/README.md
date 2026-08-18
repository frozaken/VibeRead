# Vibe Read website

The static landing page for Vibe Read, a free and open source Mac app for
voice dictation, reading selected text aloud, and configurable Cmd + E
actions.

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

Vibe Read stores history and preferences locally. Audio is temporary and is
removed after seven days by default. A user configured remote provider still
receives audio or selected text when the user asks it to process that content.
The provider applies its own terms. Users can instead configure a compatible
service running on their Mac.
