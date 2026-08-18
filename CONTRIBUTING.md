# Contributing

Thanks for helping keep Vibe Read small, understandable, and local-first.

## Product boundary

Good contributions improve the three core workflows:

- local dictation history;
- local macOS read-aloud; and
- rebindable text actions using a provider chosen by the user.

Changes that introduce accounts, subscriptions, team features, analytics,
hosted storage, cloud sync, or a mandatory Vibe Read server are out of scope.
A new network request must be user-initiated or essential to the configured
provider workflow, clearly visible in the UI, and documented in `PRIVACY.md`.

## Development setup

1. Use macOS 13 or newer and Xcode 16 or newer.
2. Open `Vibe Read.xcodeproj`.
3. Select the **Vibe Read** scheme and **My Mac**.
4. Choose a personal development team if Xcode requires signing for Run.
5. Grant Microphone and Accessibility access only to a build you trust.

The project intentionally has no third-party Swift package dependencies.

## Before opening a pull request

Run the build and tests:

```bash
xcodebuild \
  -project "Vibe Read.xcodeproj" \
  -scheme "Vibe Read" \
  -configuration Debug \
  -destination "platform=macOS" \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild \
  -project "Vibe Read.xcodeproj" \
  -scheme "Vibe Read" \
  -destination "platform=macOS" \
  CODE_SIGNING_ALLOWED=NO \
  test
```

Also check that:

- tests cover persistence, migration, retention, or shortcut behavior changed
  by the patch;
- logs never include transcript text, selected text, audio, or API keys;
- no fixture contains real personal data;
- new settings have safe local-first defaults;
- provider errors do not print request bodies or authorization headers; and
- `README.md`, `PRIVACY.md`, and `LOCAL_DATA.md` still match the implementation.

## Pull requests

Keep a pull request focused. Explain the user-visible result, privacy or data
migration impact, and how it was verified. Avoid committing Xcode user data,
DerivedData, signing assets, local databases, recordings, or secrets.

By contributing, you agree that your contribution is licensed under the MIT
License in this repository.
