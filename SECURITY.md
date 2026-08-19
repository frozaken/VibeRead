# Security policy

## Supported code

Security fixes are made on the current default branch. Historical hosted builds
and their services are retired and are not supported by this repository.

## Report a vulnerability

Do not open a public issue for a vulnerability that could expose transcripts,
recordings, API keys, or allow unwanted microphone or Accessibility access.

Use GitHub's private vulnerability reporting for the repository if it is
enabled. Otherwise, contact the repository maintainer privately and include:

- affected commit or version;
- macOS version and hardware architecture;
- concise reproduction steps;
- expected and observed behavior; and
- impact, including what data or permission boundary is crossed.

Please do not include real dictations, provider keys, or other personal data in
a report. Use synthetic samples and redact logs.

## Security model

- Provider API keys are stored in macOS Keychain, not in source code,
  preferences, or the transcript database. Groq, OpenRouter, and OpenAI each
  use one item across dictation and Cmd + E. ElevenLabs uses a dictation-only
  item. Custom dictation and custom text use separate items.
- Launching Vibe Read and opening Settings do not read Keychain. The app reads
  a saved key only after explicit verification or intentional provider use.
  A loaded key is cached in process memory until the app quits.
- Generic provider keys created by older builds are not automatically
  discovered or migrated. Users must re-enter them for the intended provider.
- Vibe Read does not request system access at startup. macOS prompts only after
  the user clicks Grant Access or intentionally uses a feature that needs the
  permission.
- Remote providers must use HTTPS. Unencrypted HTTP is allowed only for an
  explicitly configured loopback address.
- Transcript and audio files are local but not application-level encrypted.
  Use FileVault for encryption at rest.
- Accessibility permission is powerful. Install builds only from a source and
  signer you trust, and revoke permission in System Settings when no longer
  needed.
- Data sent to a configured AI provider leaves the local security boundary and
  is governed by that provider.
- A stable bundle identifier and signing identity matter for macOS permissions
  and Keychain access. Anyone distributing a build should use their own bundle
  identifier, Developer ID identity, and notarization credentials. Ad hoc
  signing is suitable only for local development.

## Maintainer release hygiene

Before publishing or distributing a build:

1. build from a reviewed, clean working tree;
2. run the tests and a secret scanner;
3. confirm no API keys, provisioning files, personal recordings, databases, or
   environment files are present;
4. review the complete Git history for secrets and private data;
5. use a fresh or reviewed squashed public history rather than the retired
   private product's full history;
6. confirm the bundle identifier and signing identity are intended for the
   release; and
7. sign and notarize binaries intended for other people.
