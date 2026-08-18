# Local data and migration

Vibe Read stores its own data on the Mac. Nothing in this directory is synced
by Vibe Read.

## Data locations

The main data directory is:

```text
~/Library/Application Support/VibeRead/
├── dictations.sqlite3
├── dictations.sqlite3-wal      # may exist while the app is running
├── dictations.sqlite3-shm      # may exist while the app is running
└── Dictations/
    └── … retained audio files
```

- `dictations.sqlite3` contains transcript history, timestamps, duration, and
  relative references to retained recordings.
- `Dictations/` contains recordings that are still inside the chosen retention
  window.
- Preferences such as shortcuts, action definitions, provider URL/model names,
  and retention settings use the standard macOS preferences system.
- The provider API key is a generic-password item in macOS Keychain. It is not
  stored in the SQLite database or preferences.

The SQLite database is not application-level encrypted. Use FileVault and a
locked macOS account if local-at-rest protection matters for your threat model.

## Retention

Transcript history has no automatic expiration. Delete an individual entry or
use **Settings → Local Data → Delete All History and Audio** to remove it.

Audio is deleted after seven days by default. The choices are immediately,
after one day, after seven days, after 30 days, or never. Cleanup runs when the
store starts, after each dictation, when the setting changes, and once a day
while the app remains open. A failed recording remains available for retry for
up to seven days even if immediate deletion is selected.

Use **Delete All Audio** to remove recordings while preserving transcript text.

## Back up or move local data

1. Quit Vibe Read so SQLite can finish its write-ahead log.
2. Copy the entire `~/Library/Application Support/VibeRead/` directory.
3. Restore that directory to the same location while Vibe Read is not running.

Copy the whole directory rather than only the `.sqlite3` file. The API key is
not included; configure it again on the destination Mac.

## Migration from earlier local builds

Earlier builds stored dictation history as JSON values in macOS preferences,
with unscoped or account-scoped keys, and placed audio either directly inside
the Dictations directory or in a nested directory.

On first launch, the local-only store automatically:

1. discovers all recognized legacy dictation-history preference values;
2. normalizes safe audio paths into the current Dictations directory layout;
3. imports all decoded rows into SQLite in a transaction; and
4. removes each legacy preference value only after SQLite confirms the import.

The import is idempotent. If decoding or persistence fails, the source value is
left in place for recovery. Transcript contents are not printed during the
migration.

This migration covers data already present on the Mac only. It does not connect
to or import from the former hosted database. Anyone who used a hosted Vibe Read
build should export any server-side data they want to retain before that service
is removed. Server-side export and deletion are operational tasks outside this
local app and repository.

## Removing all local data

Before uninstalling:

1. Use **Settings → AI Provider → Remove Key**.
2. Use **Settings → Local Data → Delete All History and Audio**.
3. Quit the app and remove `~/Library/Application Support/VibeRead/` if it still
   exists.

Other non-secret preferences may remain in the normal macOS preferences store.
