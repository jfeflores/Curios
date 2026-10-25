# Privacy — Curios

Curios is an independent, open-source Swift macOS todo app, originating in a Ghidra/Things reverse-engineering skills project. No Things user database, account or cloud service is accessed by the application. These notes describe the current encrypted-vault source, not proposed cloud/AI features. V1.0's original findings remain historical records.

## Task storage and encryption

**New profiles require enrollment before any task database is written. Existing legacy JSON profiles remain unencrypted until you explicitly choose Settings → Data → Enable Encrypted Vault.** The main window labels that legacy state. Enrollment creates a random vault master key, passphrase and independent recovery-key wrappers, and authenticated AES-256-GCM database snapshots. Tasks, notes, checklists, projects, areas, tags, dates, completion/trash state and preferences are inside the encrypted payload.

This source-build release uses system CryptoKit plus CommonCrypto PBKDF2-HMAC-SHA-256 (600,000 iterations, random 16-byte salts). It does not store the passphrase or recovery secret, use Keychain/iCloud Keychain, or claim Touch ID/Secure Enclave protection. Use a long, unique passphrase. Save and confirm the recovery key separately before enrollment. Either route decrypts the vault; losing both is unrecoverable. Swift memory copies cannot be guaranteed erased.

New profiles use:

```text
~/Library/Application Support/Curios/curios.json
~/Library/Application Support/Curios/curios.json.backup
~/Library/Application Support/Curios/curios.json.vault
~/Library/Application Support/Curios/curios.json.lock
```

The `.json` basename is retained even when its contents are binary ciphertext. `.backup` is the previous valid snapshot. `.vault` is an encrypted enrollment snapshot and migration/downgrade barrier; it intentionally retains the original enrolled state. Restoration preserves uniquely named `.recovery-*` copies. Backups/recovery/enrollment snapshots can retain deleted information.

Existing `~/Library/Application Support/Daybook/daybook.json` profiles and their sidecars remain in place; renaming must not abandon existing work or invalidate the shared lock. A current Curios profile takes precedence when both locations exist; separate profiles are not silently merged. `CURIOS_DATA_DIR` overrides the directory and discovers an existing legacy basename. `DAYBOOK_DATA_DIR` remains a compatibility override. Do not unlink persistent lock files while processes run.

Managed directories/files remain private (`0700` / `0600`), ACL-aware, no-follow/type/ownership checked and atomically replaced, with persistent locking and stale-writer rejection. The plaintext payload limit is 64 MiB; encrypted files have a separate bounded overhead allowance. These protections are not synchronization, redundant backup or secure erasure.

## Migration and retained copies

Enrollment verifies recovery material and encrypted candidates before converting the primary, valid backup and known bounded recovery files. The encrypted `.vault` snapshot is written before conversion; primary is committed last. Interrupted conversion can resume with the original enrollment credentials. Unsafe, oversized, excessive or unconvertible artifacts stop migration instead of being silently deleted/truncated. Partial conversion remains locked/recoverable; do not discard the enrollment recovery key after an error.

Close older builds before migration. Older binaries cannot open encrypted files or honor the new downgrade barrier. A missing primary with a previous backup requires explicit authenticated recovery rather than silently creating sample data. Corrupt bytes remain preserved. Restoring a backup is different from merging an import.

Migration does not securely erase prior plaintext in SSD/APFS snapshots, Time Machine, old exports, shared folders, independent sync tools or other copies. Curios does not delete OS backups or unrelated files. File existence, size, timestamps and opaque format/key identifiers remain observable.

## Unlocking, drafts and portable exports

Encrypted vaults open locked. Manual lock clears every Curios content window's session, editor/search state, undo/redo, capture/deduplication state and calendar display caches. Sleep/session/display-lock signals and approximately 15 minutes of app input inactivity also trigger locking, checked by the periodic timer. OS notification delivery is not guaranteed. Locking one process is not a guarantee that another process has cleared its own memory.

**Save edits before locking. Unsaved editor/Quick Entry drafts are cleared, not silently saved.** Manual lock warns first; automatic privacy locking cannot wait for a draft prompt. Late unlock/import/permission/editor callbacks are rejected across session changes. Plaintext already copied to the clipboard or another process is outside this boundary. Explicitly copying the recovery key may expose it to clipboard history; Curios does not clear unrelated clipboard contents automatically.

The preferred **Encrypted Backup** action creates an independent portable export protected by its own export passphrase. The live vault recovery key does not unlock that export. Store the export passphrase safely; this release does not provide an export recovery-key workflow. Explicit **Plaintext JSON Export** remains available with a warning. Both contain the whole database, including completed/trashed work and preferences. Imports validate and merge records by ID while retaining destination preferences; they do not adopt the source vault's keys. No import requests arbitrary Keychain access.

Encryption does not protect content from malware/debuggers/administrators controlling the app or OS while unlocked, guarantee removal from swap/crash artifacts, prevent screenshots, or detect malicious rollback to authentic old ciphertext. Keep independent backups and use protected destinations.

## Complementary FileVault protection

Curios offers a **read-only** `/usr/bin/fdesetup status` check and a link to FileVault settings. It never enables/disables FileVault, requests administrative privileges, handles its recovery keys or changes system settings. Unknown/error status is not presented as protected. The check describes the Mac's FileVault state, not the encryption of every external/export volume. FileVault complements the application vault by protecting volume data at rest; neither is a defense against all attacks during an unlocked session.

## Permissions and integrations

- **Calendar:** optional EventKit full-access permission is requested only when enabled. The code reads events for display, not writes. Event objects are not intentionally serialized into task storage. Selected calendar identifiers are encrypted preferences after enrollment. Disabled/revoked access and vault lock clear display caches; OS change delivery is not guaranteed.
- **Notifications:** optional, generic text only: “Curios reminder — Open Curios to review your reminders.” The OS receives opaque IDs and timing. Already scheduled generic reminders may fire while locked; no data-dependent scheduling refresh runs while locked, so schedules may become stale until unlock. No exact-delivery guarantee is made. Old app identities' notifications may need separate macOS cleanup.
- **Clipboard:** explicitly invoked bounded multiline capture only; no background clipboard collection. Recovery-key copying is an explicit action.
- **Keyboard:** a Quick Entry hotkey is registered while the app runs. Input activity monitoring is limited to Curios's own key/mouse/scroll events for idle locking; it records time, not event content. No background keystroke logging is implemented.
- **External links:** `curios://add` and legacy `daybook://add` require an unlocked/legacy-open session plus explicit preview/approval. Locked capture is rejected, not queued as plaintext. URLs can remain in browser/launcher history; do not put secrets in them.

## Network, diagnostics and future changes

No application-owned cloud backend, network API/client, login, analytics or crash-reporting service is implemented. This is source review, not packet-capture verification of all macOS framework activity. Calendars, OS backups, notification systems and browsers operate under their own policies. Local/test builds may download development dependencies; the app does not contact those package services.

Normal builds omit `CURIOS_DIAGNOSTICS` screenshot/UI-test hooks. UI regressions use separate review bundles and synthetic profiles under ignored `.analysis/`; screenshots/logs are not public release assets. Never publish live vaults—even ciphertext—recovery material, Keychain dumps, private screenshots or proprietary investigation inputs.

Before accounts/cloud/AI/integration expansion, define its own threat model, data purposes, retention, access controls, device enrollment/revocation and key recovery. Local encryption is **not cloud end-to-end encryption**. See [SECURITY.md](SECURITY.md), [the implementation record](docs/ENCRYPTED_STORAGE.md) and [the format specification](docs/VAULT_FORMAT.md).
