# Privacy — Curios V1

Curios is a local-first macOS application, formerly developed as Daybook. These notes describe current source behavior, not proposed cloud or AI features.

## Local data

Titles, notes, checklists, projects, areas, tags, scheduling/reminder dates, completion/trash state and preferences are stored as **unencrypted JSON**. The legacy location is retained intentionally:

```text
~/Library/Application Support/Daybook/daybook.json
~/Library/Application Support/Daybook/daybook.json.backup
~/Library/Application Support/Daybook/daybook.json.lock
```

Restoration can preserve a uniquely named `daybook.json.recovery-*` file. Older builds used `recovered-*`. The sidecar lock contains no task database and remains in place for process coordination. An explicit `DAYBOOK_DATA_DIR` environment setting changes the local directory.

V1 creates app-managed directories with owner-only permissions and managed files/exports with `0600` permissions, removes macOS extended ACL grants from managed objects, rejects unsafe final symlinks/nonregular or multiply linked files, and uses private staged atomic writes. Exporting does not change the permissions/ACL of the user-selected parent directory. Existing broad home/temporary directories are not chmodded. These controls rely on the OS/filesystem: they do not provide encryption, an app lock, protection from same-user malware/administrators, or secure erasure.

Backups, recovery files and exports may retain content no longer in the active database. Export contains the whole database, including completed/trashed work and preferences. A plaintext warning appears before export. OS backups, user-selected shared folders and independent folder-sync tools can copy these files; choose their destinations carefully.

Files outside the 64 MiB serialized limit or other field/collection/depth safety bounds are rejected, not truncated. Corrupt input is preserved. Explicit restoration preserves the previous primary as a private recovery copy before replacing it; keep independent backups for important data.

## Permissions and platform features

- **Calendar:** optional and requested only when enabled. EventKit's full-access permission is required to display events, but reviewed code reads rather than writes calendar events. Event objects are held for display, not intentionally serialized into task JSON. Selected calendar identifiers are stored in preferences. Disabled/revoked access clears the app's event/calendar lists when refreshed; immediate OS event delivery is not guaranteed.
- **Notifications:** optional and requested only when enabled. Content is generic: “Curios reminder — Open Curios to review your reminders.” Task/project names and notes are not included. The OS still receives opaque identifiers and reminder timing and controls delivery/previews. Requests are reconciled serially within a bounded nearest-reminder window. No promise of exact delivery is made.
- **Old Daybook notifications:** changing the bundle identity does not grant Curios control over notifications registered to another app identity. Manage old notifications through macOS/the old app. Calendar/notification permissions may need to be granted again for Curios.
- **Clipboard:** read only by explicit multiline capture. Input is bounded before splitting into tasks; no background clipboard collection is implemented.
- **Keyboard:** a global Quick Entry hotkey is registered while the app runs. Other keyboard routing is scoped to the app's active window; no background keystroke logging is implemented.
- **External links:** `curios://add` and legacy `daybook://add` show a preview before a confirmed write. Input is allow-listed and bounded; repeated approved captures are deduplicated for the session. List navigation is also supported. URLs may be retained by browsers/launchers, so never put secrets in query strings. Follow links in task notes only when you trust their destination.

## Network and diagnostics

No application-owned cloud backend, network API/client, authentication, advertising, analytics or crash-reporting service is implemented. This is source review, not a claim that all macOS framework/network activity has been packet-captured. Independently configured calendars, notification services, backup systems and browsers operate under their own policies.

Normal builds omit developer screenshot/UI-test hooks. `DAYBOOK_DIAGNOSTICS=1 ./scripts/build.sh` deliberately compiles those hooks for development; `scripts/ui-test.sh` uses a separate review bundle and synthetic profiles. Keep diagnostic screenshots/logs private. No background task/calendar-content telemetry is implemented.

Curios does not read Things' user database or connect to Things Cloud. Proprietary development/reference inputs live only in the ignored local investigation folder and must not be distributed with public source.

## Future changes

Before adding cloud, accounts or AI, define and disclose identity, data purposes, processors/regions, retention, access controls, encryption/key recovery, export/deletion and diagnostic handling. V1 makes no end-to-end-encryption or provider-blind-storage promise. See [SECURITY.md](SECURITY.md) and [the hardening record](docs/V1_HARDENING.md).
