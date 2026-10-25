# Curios

**Project type: Reverse Engineering (Ghidra + Things), evolving into an independent open-source Swift todo app.** Built in Swift, SwiftUI and AppKit. Curios is a native, local-first macOS application under [Apache-2.0](LICENSE), gradually evolving into its own product with more features—not a commitment to remain a Things clone.

[GitHub](https://github.com/jfeflores/Curios) · [Roadmap](ROADMAP.md) · [Security](SECURITY.md) · [Privacy](PRIVACY.md) · [Encrypted storage](docs/ENCRYPTED_STORAGE.md) · [Product plan](docs/CURIOS_PRODUCT_PLAN.md)

## Reverse-engineering origin: Ghidra and Things

**This project began by studying Things with Ghidra, through REA, to practice and demonstrate reverse-engineering expertise and technical skills.** The earlier prototype was called Daybook. Bounded analysis of shipped application artifacts was combined with publicly documented behavior; recovered wrappers were not treated as proof of complete algorithms. See the [investigation, evidence and limitations](docs/REVERSE_ENGINEERING.md).

Curios uses an independent Swift implementation, original branding/icon and synthetic sample content. This repository does **not** distribute proprietary binaries, copied decompiled source, vendor artwork, private task data, cloud protocols or credentials. The app does not access a Things user database, Things account or Things Cloud. Curios is not affiliated with or endorsed by Cultured Code.

The investigation is the starting point, not the product's permanent specification. Future work will improve Curios as an independent open-source planner: useful daily commitments, better restart context, accessible workflows, trustworthy imports and additional features introduced gradually.

## Build and test

Requires macOS 14+, a matching Swift 6+/Xcode toolchain, and Python 3 for the standalone test launcher. **The application has no third-party Swift package dependencies.** It uses Apple CryptoKit, CommonCrypto and system frameworks. The optional independent interoperability check has separate Python test dependencies.

```sh
./scripts/test.sh
./scripts/build.sh
open build/Curios.app
```

The build creates an **ad-hoc-signed development app**, not a notarized distributor/App Store release. The source version is 1.1.0; passing checks are not a guarantee of vulnerability-free software. Building does not open vendor task data or grant calendar/notification permissions.

With a matching Xcode toolchain:

```sh
swift test
swift run Curios
```

The scripts accommodate the existing local Command Line Tools/SDK mismatch without installing/changing toolchains. Override the SDK with `CURIOS_SDK=/path/to/MacOSX.sdk`; the old `DAYBOOK_SDK` remains a compatibility fallback. Isolate parallel test outputs with `CURIOS_TEST_BUILD_DIR=.build/my-tests ./scripts/test.sh`.

## Encrypted storage and FileVault

**New profiles require enrollment before task data is written. Existing legacy profiles are not silently migrated:** use **Settings → Data → Enable Encrypted Vault**. Their main window displays “encryption off” until migration.

- **AES-256-GCM** encrypts the full task/preferences payload and managed backups/recovery snapshots; headers are authenticated and inputs bounded.
- A random vault key is unlocked by a long unique passphrase using **PBKDF2-HMAC-SHA-256, 600,000 iterations**, or an independent random recovery key. Save and re-enter the complete recovery key before enrollment. Either credential decrypts the vault; losing both is unrecoverable.
- **Encrypted Backup** creates a portable copy using independent key material and its own export passphrase. The live recovery key does not unlock that export. Explicit **Plaintext JSON Export** remains available with a warning.
- Encrypted vaults open locked. Manual lock, sleep/session/display-lock signals and approximately 15 minutes of Curios input inactivity clear session content/history/caches. **Save edits first: unsaved editor/Quick Entry drafts are cleared.** Manual lock warns; automatic privacy locking cannot wait for a prompt.
- **FileVault is complementary protection.** Curios provides a read-only status check and settings link. It never turns FileVault on/off, requests administrator privileges, collects its recovery key or changes system encryption settings. Status does not verify external/export drives.

Keep recovery material separately and retain independent encrypted backups. Close older builds before migration. Conversion is bounded/resumable and preserves original content in an encrypted enrollment snapshot; it does not erase prior plaintext from APFS/Time Machine, old exports or other copies. Missing keys/corrupt data never silently create a replacement database.

This release does **not** claim Keychain/Touch ID/Secure Enclave unlock, Argon2, cloud E2EE, secure deletion, guaranteed memory erasure, malicious rollback detection or protection from a compromised app/OS while unlocked. Ordinary mutations still serialize/encrypt complete snapshots synchronously; a scalable transactional repository remains future work.

See [PRIVACY.md](PRIVACY.md), [implementation evidence and limitations](docs/ENCRYPTED_STORAGE.md), and the [versioned format](docs/VAULT_FORMAT.md).

## What Curios contains

- Inbox, Today/Evening, Upcoming, Anytime, Someday, completed work and restorable Trash.
- Projects/headings/areas, nested and inherited tags, filtering and search.
- Notes/Markdown preview, checklists, independent start/deadline dates, reminders, completion and cancellation.
- Repeating task/project templates with regular and after-completion schedules.
- Quick Entry, keyboard commands, multi-selection, batch edits, duplication, basic drag/drop and session undo/redo.
- Encrypted vault/backup/recovery plus schema-v1 Curios/legacy JSON interchange; import merges records by ID and retains destination preferences.
- Optional read-only EventKit calendar display and generic local reminders.
- Multiple windows, appearance preferences and confirmed external capture.

**Not implemented:** accounts, cloud backend/sync, Siri/App Intents, widgets, mobile/watch clients, third-party task importers, mail capture or collaboration. These are [roadmap proposals](ROADMAP.md), not shipped capabilities. Notification timing/opaque IDs remain OS metadata; already scheduled generic reminders may fire while locked and can become stale until unlock.

## Your data and legacy compatibility

New profiles use `~/Library/Application Support/Curios/curios.json`, with `.backup`, `.vault`, `.lock` and uniquely named `.recovery-*` sidecars. The `.json` basename can contain binary ciphertext. `.vault` is the encrypted enrollment snapshot/barrier and intentionally retains the original enrolled state.

Existing `~/Library/Application Support/Daybook/daybook.json` profiles retain their location/basename and lock so renaming does not abandon existing work. A current Curios profile takes precedence if both locations exist; independent profiles are not silently merged. Older recovery names are discovered during migration. **Never unlink a persistent `.lock` file while processes run.**

Managed files remain private/ACL-aware and atomically replaced, with no-follow/type/ownership checks, persistent cross-process locking and stale-writer rejection. Plaintext payloads are capped at 64 MiB; ciphertext has a bounded overhead allowance. Field/collection/depth and recurrence work limits remain enforced. A stale process must reload, not silently overwrite newer work.

Develop only with synthetic, isolated profiles:

```sh
CURIOS_DATA_DIR="$PWD/.analysis/my-test-data" build/Curios.app/Contents/MacOS/Curios
```

`CURIOS_DATA_DIR` discovers an existing legacy basename in that folder; `DAYBOOK_DATA_DIR` still selects the legacy basename for compatibility. Do not point unattended tests at a normal profile. The active source targets are **Curios** and **CuriosCore**; remaining Daybook names document compatibility or historical evidence.

## Capture links

Both `curios` and legacy `daybook` schemes remain registered:

```text
curios://add?title=Plan%20the%20week&when=tomorrow&notes=Three%20priorities
curios://show?list=upcoming
```

Capture requires an unlocked/legacy-open session and explicit preview/approval. Locked links are rejected, not queued as plaintext. Inputs are allow-listed/bounded and approved duplicates are suppressed per session. Do not put secrets in URLs—browsers/launchers may retain them. Curios never registers or impersonates the vendor's `things` scheme.

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
| Lock encrypted vault | ⌃⌘L |

## Verification and developer diagnostics

Implementation checkpoint: `2072477` — encrypted vault, recovery, complementary FileVault guidance and the Curios module rename. The checks below cover that implementation; a source commit does not imply a published/notarized binary.

Local verification includes **83 core/domain/security tests**, **19 existing plus 9 encrypted application groups**, **three isolated native UI scenarios**, and independent Python/OpenSSL passphrase/recovery interoperability. Normal/diagnostic builds, SourceKit checks and staged secret/content review are additional gates; these checks are not a third-party security audit. Remote CI for new changes requires an actual push and is not inferred from local results.

```sh
./scripts/ui-test.sh
```

The UI launcher explicitly compiles `CURIOS_DIAGNOSTICS`, uses a separate review bundle and synthetic profiles under ignored `.analysis/`, and checks native checkbox events plus encrypted lifecycle/view teardown. It does not automate every credential-field interaction or prove all OS permission/lock/accessibility behavior. Normal builds omit these hooks.

For optional independent format verification after `scripts/test.sh`:

```sh
python3 -m venv .build/interop-python
.build/interop-python/bin/python -m pip install cryptography==50.0.2 cffi==2.1.1 pycparser==3.12
CURIOS_INTEROP_PYTHON=.build/interop-python/bin/python ./scripts/interop-test.sh
```

## License, contributions and publication

Original project source/documentation is **Apache-2.0**. Contributors must have the right to submit their work. Apple frameworks/system symbols, test dependencies and third-party trademarks retain their respective terms; this license does not grant rights to proprietary investigation inputs or establish legal clearance for them.

Publish reviewed source only. Never commit `.analysis/`, `.build/`, `build/`, virtualenvs, credentials/signing material, real databases/exports—even ciphertext—recovery kits, private screenshots or raw decompiler evidence. Use [private vulnerability reporting](SECURITY.md), not public issues containing sensitive material.
