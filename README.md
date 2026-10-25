# Curios

A native, local-first macOS task manager, published under the [Apache License 2.0](LICENSE). **V1 is a source release of a young application, not a claim of vulnerability-free software or a notarized App Store release.**

[GitHub](https://github.com/jfeflores/Curios) · [Roadmap](ROADMAP.md) · [Security](SECURITY.md) · [Privacy](PRIVACY.md) · [V1 hardening](docs/V1_HARDENING.md) · [Product plan](docs/DAYBOOK_PRODUCT_PLAN.md)

Curios began as the independent Daybook prototype studying publicly described Things workflows. It uses original SwiftUI/AppKit code, an original icon and synthetic sample content. It is not affiliated with Cultured Code. No proprietary binaries, vendor artwork, private task data, vendor cloud access or credentials belong in this repository.

## Build and test

Requires macOS 14+, a matching Swift 6+/Xcode toolchain, and Python 3 for the standalone test launcher. There are no third-party Swift package dependencies.

```sh
./scripts/test.sh
./scripts/build.sh
open build/Curios.app
```

The build creates a **locally ad-hoc-signed** development application. It is not notarized and has no developer-distribution identity. Building does not access another application's task data or grant calendar/notification permissions.

On a matching Xcode toolchain, the package supports:

```sh
swift test
swift run Curios
```

The standalone scripts also support the local beta Command Line Tools installation whose SwiftPM interfaces do not match its compiler. They select the already-installed macOS 15.4 SDK when available; they do not install or change a system toolchain. Override with `DAYBOOK_SDK=/path/to/MacOSX.sdk` if needed. CI uses the runner's Xcode toolchain; an actual remote CI result is separate from local verification.

For isolated parallel test outputs:

```sh
DAYBOOK_TEST_BUILD_DIR=.build/my-tests ./scripts/test.sh
```

## What V1 contains

- Inbox, Today/Evening, Upcoming, Anytime, Someday, completed work, and restorable Trash.
- Projects, headings, areas, nested/inherited tags, filtering and search.
- Notes/Markdown preview, checklists, independent start dates and deadlines, reminders, completion and cancellation.
- Repeating task/project templates with regular and after-completion schedules.
- Quick Entry, keyboard commands, multi-selection, batch edits, duplication, basic drag/drop and session undo/redo.
- Schema-v1 Curios/legacy Daybook JSON import/export, previous-valid backup and explicit recovery.
- Optional read-only EventKit calendar display and privacy-preserving local reminders.
- Multiple windows, light/dark/system appearances, and a separate capture confirmation for external links.

**Not implemented:** accounts, cloud sync/backend, Siri/App Intents, widgets, mobile/watch clients, third-party task importers, mail capture, or collaboration. These are [roadmap proposals](ROADMAP.md), not advertised V1 capabilities. Original prototype boundaries are recorded in [the historical feature matrix](docs/FEATURE_PARITY.md).

## Security and data integrity

V1 hardening adds:

- Private app-managed directories and files, removal of macOS ACL grants on managed objects, descriptor-pinned/no-follow file operations, and private atomic replacement.
- A shared 64 MiB serialized save/load ceiling, bounded reads before allocation, indexed relationship validation, field/depth limits, and bounded/resumable recurrence work.
- A persistent sidecar file lock plus observed-revision checks. A stale process must reload instead of silently overwriting newer work.
- URL capture preview/confirmation, strict allow-listed inputs, size limits and per-session approved-capture deduplication.
- Generic notification text rather than task/project content, and serialized scheduling reconciliation.
- Developer screenshot/UI-test hooks excluded from normal builds.

See [the hardening record](docs/V1_HARDENING.md) for verification and remaining limits. These protections do **not** encrypt your tasks, protect them from malware running as your user, guarantee OS notification delivery, or replace independent backups. If a save reports that the database changed elsewhere, preserve your unsaved text and reopen/reload before editing; no automatic multi-device merge is provided.

## Your data and legacy compatibility

Curios deliberately keeps the existing Daybook data location and schema so upgrading the app name does not abandon existing work:

```text
~/Library/Application Support/Daybook/daybook.json
~/Library/Application Support/Daybook/daybook.json.backup
~/Library/Application Support/Daybook/daybook.json.lock
```

Restoration can preserve `daybook.json.recovery-*` copies; older builds used `recovered-*`. The persistent lock file is intentional—do not unlink it while processes are running. User exports are named `Curios-YYYY-MM-DD.json` and contain the whole database, including completed/trashed work and preferences.

**All are unencrypted.** Recovery copies, backups, exports and OS backup systems may retain deleted information. The first launch creates original sample tasks. Existing data outside V1's documented safety bounds is preserved and rejected rather than truncated or silently overwritten. See [PRIVACY.md](PRIVACY.md).

Use synthetic, isolated data when developing:

```sh
DAYBOOK_DATA_DIR="$PWD/.analysis/my-test-data" build/Curios.app/Contents/MacOS/Curios
```

This environment override remains an intentional local configuration, not a network feature. Do not point unattended tests at your normal profile.

## Capture links

Both the new and legacy schemes are registered:

```text
curios://add?title=Plan%20the%20week&when=tomorrow&notes=Three%20priorities
curios://show?list=upcoming
```

`add` opens a preview: nothing is saved until you approve it. Identical approved captures are deduplicated for the running session. Only add and allow-listed list navigation are supported; unknown fields, duplicate query names, malformed dates and oversized input are rejected. Do not put secrets in URLs—browsers and launchers may retain them. The app never registers or impersonates the vendor's `things` scheme.

## Useful shortcuts

| Action | Shortcut |
|---|---|
| New task / project / heading | ⌘N / ⌥⌘N / ⇧⌘N |
| Complete / cancel | ⌘K / ⌥⌘K |
| Quick Find | ⌘F, or type outside an editor |
| Inbox through completed work | ⌘1 … ⌘6 |
| When / Today / Evening | ⌘S / ⌘T / ⌘E |
| Anytime / Someday / deadline | ⌘R / ⌘O / ⇧⌘D |
| Save editor / Quick Entry | ⌘Return / ⌃⇧Space |
| Multiline paste / sidebar | ⇧⌘V / ⌘/ |

## UI regression diagnostics

```sh
./scripts/ui-test.sh
```

This explicitly compiles `DAYBOOK_DIAGNOSTICS`, launches a separate review bundle and creates synthetic profiles under ignored `.analysis/`. It tests native checkbox events, visible state and disk readback. Ordinary builds ignore screenshot/UI-test launch hooks. This is not a full external accessibility or OS-permission audit.

## License and contributions

Original project source/documentation is made available under **Apache-2.0**; see [LICENSE](LICENSE). Contributors must have the right to submit their work under that license. Apple frameworks/system symbols and third-party trademarks remain under their respective terms; this declaration does not license vendor artifacts or establish legal clearance for them.

Publish only reviewed source. Never commit `.analysis/`, `.build/`, `build/`, credentials/signing material, real data/exports, raw decompiler evidence or private screenshots. Use the security policy for private reports rather than posting sensitive material in public issues.
