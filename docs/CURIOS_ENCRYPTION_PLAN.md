# Curios encrypted storage — proposed architecture

**Status: original planning record, subsequently authorized for implementation.** This proposal was based on Curios V1 commit `49e3667`; its Daybook source paths describe that snapshot. The source-build implementation now uses CryptoKit, platform PBKDF2 and recovery unlock; Keychain, Argon2 adoption and the SQLite rewrite remain deferred. See [the implementation and verification record](ENCRYPTED_STORAGE.md), [wire format](VAULT_FORMAT.md) and [current privacy behavior](../PRIVACY.md). The proposal is not a security certification or a claim that every future phase shipped.

## 1. Recommendation

Yes: Curios can encrypt its tasks and other stored application data.

**For the current JSON-based application, use CryptoKit AES-256-GCM to encrypt the complete serialized database, with a random vault master key and separately managed unlock methods.** Cover automatic backups and recovery copies, not just the primary file. Provide an independently usable recovery method before migrating important data.

- **Current source/ad-hoc builds:** plan a passphrase-unlocked vault without requiring an Apple developer account. Use a vetted password KDF, not a password hash used directly as an AES key.
- **A properly signed/provisioned distribution:** offer macOS Keychain convenience, with optional system user-presence authentication. Validate the actual macOS Keychain backend, entitlements and update behavior first; this is not guaranteed by today's build script.
- **Portable backups:** support independently encrypted exports. Do not make access depend solely on a particular Mac's Keychain.
- **If the next authorized milestone is already a SQLite repository rewrite:** evaluate SQLCipher as part of that rewrite instead of shipping two successive storage migrations. The same unlock, recovery and app-lock requirements still apply.

This is the smallest defensible encryption change for V1, not a solution to the JSON store's long-term scalability limits. Do not implement both persistence backends speculatively.

## 2. Current storage boundaries

| Boundary | Reviewed behavior | Encryption consequence |
| --- | --- | --- |
| `Sources/DaybookCore/Persistence.swift` | Encodes/decodes the complete database as JSON; validates before use; enforces a 64 MiB serialized limit. | Put the authenticated encryption boundary around the entire serialized payload. Keep domain/schema validation after decryption. |
| Managed files | Legacy `Daybook/daybook.json`, `.backup`, `.recovery-*`; older `recovered-*` files may exist. `DAYBOOK_DATA_DIR` changes the directory. | Inventory all managed copies. A plaintext backup defeats primary-file encryption. Keep compatibility discovery for legacy locations. |
| Filesystem integrity | Descriptor-pinned operations, `0700` directories, `0600` files, ACL removal, unsafe-file rejection, private staged writes, cross-process sidecar locking and observed revisions. | Preserve these protections. Encryption does not replace atomicity, permissions or stale-writer rejection. Never unlink the persistent `.lock` file while processes run. |
| `Sources/Daybook/AppStore.swift` | Eager load at initialization, sample database only if absent, synchronous transactions, whole-database undo/redo snapshots, asynchronous import. | Introduce explicit vault states and a serialized storage boundary. Missing keys or canceled unlock must never be treated as an absent database. |
| Import/export | Whole-database JSON, including completed/trashed records and preferences; export warns that it is plaintext. | Encrypted portable export should be the default export choice for an encrypted vault; retain explicit, warned plaintext interchange. |
| `Sources/Daybook/Integrations.swift` | Generic notifications, EventKit display caches, Quick Entry and diagnostics-only screenshots. | An app lock must cover every window, editor, cache and asynchronous callback, not just hide the main view. |
| `scripts/build.sh` / `Package.swift` | macOS 14 minimum; system Swift frameworks; ad-hoc signing; no provisioned Keychain configuration. | CryptoKit is available at the deployment target. Production Keychain access needs a separate signing/platform gate. |

The encrypted payload includes titles, notes, checklists, projects, areas, tags, dates, completion/trash state and preferences. Keep task IDs, recurrence state and relationship validation intact.

## 3. Threat model and honest limits

### Intended protection

- Someone obtains the vault file, backup, recovery copy or encrypted export **without its unlock material**.
- A user accidentally puts an encrypted copy into a shared folder or backup destination; task contents remain encrypted, subject to passphrase strength and correct key handling.
- Ciphertext/header modification, truncation or a wrong key is detected before any decoded database is exposed or written back.
- Optional app locking reduces casual exposure when an unlocked computer is handed to another person.

### Not a promise

- Protection from malware, a debugger or a privileged attacker controlling the app/OS while data is unlocked. The app must use plaintext and symmetric keys in memory.
- Perfect memory erasure in Swift/SwiftUI, protection from all swap/hibernation/crash artifacts, or prevention of screenshots and clipboard copies.
- Hiding file existence, size, filesystem timestamps or all OS integration metadata.
- Recovery of plaintext already copied into Time Machine/APFS snapshots, external backups, old exports, URL histories or independently synced folders.
- Availability against deletion/ransomware, or malicious rollback detection. An older authentic ciphertext is still authentic; existing stale-write checks are not a cryptographic anti-rollback system.
- Cloud end-to-end encryption. No Curios sync/backend exists, and local encryption does not make a future server provider-blind.

Recommend FileVault and protected backup destinations as complementary controls. FileVault protects volumes; it does not keep a file encrypted when an authorized process copies its plaintext elsewhere. [S9]

## 4. Compare the approaches

| Approach | Benefits | Costs / limitations | Fit |
| --- | --- | --- | --- |
| FileVault plus current permissions | No Curios data migration; system-wide offline protection. | Not an independent app vault; authorized reads/exports still yield plaintext. | Baseline defense, not the requested feature. |
| CryptoKit whole-store AES-GCM | Native framework; confidentiality and authentication; retains current domain model and most hardened file machinery. | Reencrypts a complete snapshot on save; custom envelope/migration/key lifecycle must be reviewed. | **Recommended for current V1.** |
| CryptoKit ChaCha20-Poly1305 | Also authenticated encryption through a system API. | Does not solve key management or whole-store scaling. No demonstrated Curios-specific advantage over AES-GCM. | Sound alternative; pick one cipher suite initially. |
| SQLCipher database | Encrypted SQLite pages, transactions/indexes, mature encryption implementation; natural fit for a future repository. | Rewrite JSON persistence and queries, validate migration and WAL/temp handling, integrate/maintain a dependency. It does not supply app unlock or key recovery. | **Recommended candidate if SQLite work is next.** |
| Per-field/per-record encryption over plaintext storage | Can fit a deliberately designed future E2EE protocol. | Plaintext indexes/relationships may leak; complicates search, integrity, migrations and sync. | Not the first local-only implementation. |
| Password-protected disk image/container | Can protect a mounted directory without changing the schema. | Mount lifecycle and automation complicate UX; mounted data is readable; external copies/exports remain a separate problem. | User workaround, not the integrated product design. |

SQLCipher Community is BSD-style licensed with attribution requirements; commercial binaries have different terms. Curios can remain Apache-2.0 while retaining applicable dependency notices. SQLCipher needs its own SQLite build, not a `PRAGMA` applied to Apple's ordinary SQLite. Verify that a key is supplied and that `cipher_version` identifies SQLCipher: an unkeyed SQLCipher connection can create plaintext. Encrypt journal/WAL page content and disable file-based temporary stores as documented; test all resulting artifacts. [S6–S8]

## 5. Key hierarchy and unlock policy

Separate **the data encryption key**, **how the user unlocks it**, and **whether the UI is locked**.

### Proposed hierarchy

1. Generate a random 256-bit vault master key (VMK) and random opaque vault ID using system cryptographic randomness. Never derive either from device identifiers, paths or task data.
2. Derive a content key from the VMK with HKDF and a versioned purpose label. Use separate labels/keys for distinct cryptographic purposes. HKDF is appropriate here because the VMK is high-entropy; it is not a password KDF.
3. Store only authenticated **wrapped VMK** slots alongside ciphertext. A slot may be unlocked by a device Keychain key, a passphrase-derived key, or a random recovery secret. Bind each slot to its vault ID, key generation, slot type and parameters.
4. The plaintext device unlock key belongs in Keychain, not next to the file. Never place keys/passphrases/recovery secrets in `UserDefaults`, the plist, environment variables, launch arguments, logs, Git or app source.
5. Generate an independent 256-bit recovery secret with a human-transcribable encoding and checksum. It wraps the VMK under a distinct purpose-derived key. It is not the VMK itself. Require the user to confirm it before migration; recommend storing it separately, such as in a password manager or offline copy.

Unlock slots are alternatives, not additive factors: access is only as strong as the weakest enabled route. Adding a device slot without user presence can weaken a passphrase-only policy; explain that tradeoff before enabling convenience unlock. Recovery intentionally bypasses ordinary unlock, so its secret needs equivalent care.

These are architectural boundaries, not a frozen wire protocol. Specify exact encodings and authentication inputs, obtain a cryptographic design review, and create independent test vectors before implementing the format.

### Passphrase route

For source builds, the proposed initial route is a passphrase plus recovery secret:

- Prefer **Argon2id from a vetted, pinned implementation** if accepting that dependency. Review provenance, license, Swift/native integration and supported builds before selecting a package. Do not write a new Argon2 implementation.
- A dependency-minimal alternative is **PBKDF2-HMAC-SHA-256 via the platform CommonCrypto implementation**, with a deliberately documented resistance/performance tradeoff. Argon2id is memory-hard; PBKDF2 is not. Neither a library choice nor use of PBKDF2 alone implies FIPS certification.
- OWASP's current password-storage baselines include Argon2id at 19 MiB / 2 passes / parallelism 1, and PBKDF2-HMAC-SHA-256 at 600,000 iterations. These are reference floors for evaluation, not a complete vault protocol or a benchmark result for Curios. Calibrate on supported Macs and set explicit accepted minimum/maximum parameters. [S10]
- Use a random salt of at least 16 bytes per new passphrase slot, store the KDF ID and bounded parameters, and derive a 256-bit wrapping key. Salt is public; passphrase and derived key are not.
- Bound header lengths, password input and KDF resource usage **before** performing expensive work. Run derivation off the UI actor. Reject unsupported/excessive parameters rather than silently weakening them.
- Specify password byte encoding/versioning, support Unicode and never silently truncate or trim it. Provide clear retry/cancel behavior without logging input.
- Unlock once per session, not on each edit. A passphrase change normally replaces its VMK wrapper; it does not require changing every task.

Do not use SHA-256(password), HKDF(password), a fixed bundled secret or reversible obfuscation as the protection.

### Keychain route and the current build caveat

Apple distinguishes macOS file-based/login Keychains from the data-protection Keychain. `SecItem` defaults to the former on native macOS; selecting the latter explicitly matters. Apple recommends the data-protection implementation and documents its signing/access-group/provisioning requirements. The current ad-hoc build must not be assumed to satisfy them. [S2–S4]

For a validated distribution configuration:

- Use `SecItem` with the data-protection Keychain explicitly selected; scope the item to Curios's authorized group and an opaque vault ID.
- Propose `WhenUnlockedThisDeviceOnly`, `synchronizable = false`, and optional `SecAccessControl` user presence. These are policy proposals to verify on actual supported macOS versions, not assumptions that all iOS lock behavior applies unchanged.
- `ThisDeviceOnly` deliberately does not migrate to another device. A ciphertext file and an ordinary machine backup are not an adequate cross-device recovery guarantee. [S5]
- Test add/read/update/delete, access denial, cancellation, sleep/screen lock, logout, reboot, app rebuild/update, moved app bundles and changed signing identity. Validate access after a real update before deleting any previous unlock item.
- Do not silently fall back to a different Keychain backend, synchronizable storage, plaintext persistence or weaker authentication when access fails. Keep the vault locked and offer the recovery/passphrase path explicitly.
- Self-build users can remain on passphrase unlock. A separately labeled legacy-login-Keychain convenience route should be considered only if later justified and tested; do not market it as identical protection.

A Touch ID dialog that merely hides the UI is not encryption-backed access control. If user presence is promised, enforce it in the key retrieval/wrapping policy and invalidate reusable authentication contexts on lock.

**Secure Enclave is optional, not a prerequisite.** The documented Security framework route uses enclave-generated asymmetric keys; it is not a place to import an arbitrary AES VMK. A hardware-backed wrapping/key-agreement design adds hardware, enrollment and recovery constraints. Defer it unless the threat model warrants it. [S11]

### Rotation, revocation and recovery

- Retain the key generations necessary to read supported backups until those copies are deliberately retired. Test backup restoration after password and device-key changes.
- Rotating a wrapper does not revoke old ciphertext containing the old wrapper. Changing a passphrase does not make copies protected by the old passphrase inaccessible.
- If unlock material was compromised, rotate the VMK/content key for subsequent data, regenerate recovery material, and explain that previously copied data cannot be clawed back.
- Do not offer "reset password" as though it decrypts a vault. Without any usable unlock method, data is unrecoverable. A destructive new-vault action must preserve the old encrypted files unless the user separately confirms deletion.

## 6. Encrypted envelope and persistence boundary

Proposed logical structure:

```text
bounded public header:
  magic + envelope version + cipher suite + content kind
  opaque vault ID + key generation + bounded unlock slots
  bounded lengths and KDF metadata (where applicable)

authenticated encrypted body:
  fresh nonce + ciphertext + authentication tag
  plaintext only after authentication: versioned Curios/Daybook database JSON
```

- Use CryptoKit AES-GCM with a 256-bit content key, fresh cryptographically random 96-bit nonce per new encryption and full 128-bit tag. Let the library generate nonces in production; do not use dates, a restored counter or a fixed nonce. Test and review the per-key usage/rotation policy. Never reuse a nonce with the same key. [S1]
- Authenticate the exact encoded header bytes as associated data. Each wrapped-key slot also authenticates its own purpose and identity metadata. Freeze field lengths, encoding and domain separation in the protocol review. No task names, dates or collection counts belong in the public header.
- Reject unknown versions/ciphers, malformed lengths, excess slots, invalid tags and trailing data. Authenticate before JSON decoding or publishing a database. Do not retry failed decryption as plaintext JSON.
- Keep inner database-schema version separate from envelope/export versions. Preserve schema-v1 data compatibility without claiming old binaries can open encrypted files.
- Preserve the **64 MiB plaintext serialized limit**. Define a separate bounded encrypted-file allowance for overhead; proposed maximum overhead is 64 KiB, with a much smaller explicit header/slot cap. Both encrypted save and load must use the same limits. Do not reduce usable legacy payload size accidentally or allow unbounded allocation based on a header.
- Use binary ciphertext, not base64-in-JSON, to avoid unnecessary size expansion. No compression initially; do not introduce decompression bombs.
- Encrypt before writing the staged file: staged files, primary, automatic backups and newly generated recovery copies must contain ciphertext. Backups may copy already authenticated ciphertext without decrypting to a temporary file.
- Keep the existing filesystem checks, durable staging, persistent lock and observed-revision checks. A proposed `VaultRepository`/storage actor serializes mutations; it does not eliminate the need for cross-process locking.
- Keep expensive serialization/encryption/file work off the main actor. Publish UI state only after durable success; serialize rapid edits without lost acknowledgments. Keep existing recurrence/import/input bounds. Measure latency, peak memory and temporary-disk demand at the size limit; full-store encryption is not a scaling optimization.
- Prompt for credentials outside the file lock, then reacquire/recheck the observed revision before committing. Never hold a cross-process lock across a user authentication dialog.

## 7. App lock is a separate feature

Use explicit states such as `unconfigured`, `legacyPlaintext`, `locked`, `unlocking`, `unlocked`, `migrating` and `recoveryRequired`. Distinguish missing vault, missing key, unavailable Keychain, canceled authentication, corrupt data and an unsupported version.

A failed/canceled unlock must not create sample data, overwrite the primary, restore plaintext automatically or generate a replacement key for an existing vault. All save/undo/redo/export/restore/import/capture operations require the appropriate state, including direct command handlers.

Proposed defaults: encrypted vaults open locked; manual Lock is always available; lock on screen lock/session deactivation and after a disclosed inactivity interval, subject to platform verification. App focus loss alone is not a reliable OS screen-lock signal. Multiple processes have independent decrypted sessions: locking one instance cannot honestly promise that all other instances are locked without a separate coordination mechanism.

On lock:

- Replace all main/Quick Entry/settings/editor windows with a non-content lock surface, including accessibility exposure and search results. Closing the last window is not sufficient: the current app remains running.
- Clear published database state, undo/redo snapshots, editor drafts, search strings/results, completion state, pending capture, and the content-bearing approved-capture deduplication list. Clear calendar/event display caches and release keys/authentication contexts where possible.
- Serialize lock with durable transactions. Resolve or explicitly discard unsaved drafts; never silently claim they were saved. Screen-lock privacy masking must not wait indefinitely on a draft prompt.
- Invalidate the session generation and reject late import/decrypt/notification/editor callbacks from the prior session. Cancel work where practical; cancellation alone is not a correctness guard.
- Disable background recurrence writes and data-dependent integration refresh while locked. Quick Entry and URL capture require unlock and retain explicit capture confirmation; do not persist incoming plaintext to a queue.
- Avoid content in logs, diagnostic screenshots, window titles and state restoration. Do not claim guaranteed zeroization of Swift strings/value copies.

Keep notifications generic. A proposed default is to leave already scheduled generic reminders eligible to fire while locked, without refreshing them from decrypted data; disclose that identifiers/timing remain in OS storage and that reminders may become stale until unlock. A stricter setting may clear owned reminders on lock. Notification content must never gain task text as a convenience workaround.

Plaintext deliberately copied to the system clipboard, displayed by another process or recorded in URL histories is outside this vault boundary. Do not erase unrelated clipboard data automatically. Defer Spotlight/widgets/Siri content exposure until each integration has its own explicit locked-state policy.

## 8. Migration, backups and downgrade safety

Migration is a resumable, failure-tested workflow, **not** `load JSON; overwrite with encrypted bytes`.

1. Ask the user to close older Curios/Daybook instances and explain recovery, plaintext remnants, export and downgrade behavior. Inventory primary, backup and known legacy recovery names using safe file operations; do not scan unrelated directories.
2. Enroll and verify independent recovery before changing files. Establish the selected unlock route; if Keychain enrollment fails, stop or explicitly select the passphrase route—never downgrade silently.
3. With the existing sidecar coordination, read and validate the observed primary. Before commit, stage encrypted primary/backup candidates and a verified encrypted pre-migration snapshot, read them back, authenticate, decode and compare IDs/relationships/preferences. Preserve originals until encrypted replacements and recovery have been verified.
4. Use a private resumable migration journal/state marker containing no task text or keys. Reacquire the lock and verify revisions before each commit. Atomic rename is atomic **per file**, not across primary, backup, journal and Keychain; document every crash state and its recovery action.
5. Retain the current primary basename and persistent lock for the first encrypted format, despite the legacy `.json` suffix. Old V1 then encounters unsupported bytes and fails read-only rather than treating a newly named store as absent and creating another plaintext database. Test old-process stale saves. Warn users not to run old binaries or restore their legacy backups after migration; old software cannot honor the new policy.
6. Convert valid legacy backups and bounded recovery artifacts to encrypted counterparts without writing new plaintext staging files. Corrupt but bounded recovery bytes can be protected as an explicitly typed opaque recovery payload, not misrepresented as a valid database.
7. Unsafe, oversized or unconvertible legacy recovery files are a stop/report condition, not permission to delete/truncate/read them unboundedly. Present explicit preservation/remediation choices. Any retained plaintext artifact means coverage is partial and must remain visible to the user.
8. Verify reopening after a process restart and verify that the actual encrypted migration snapshot opens with the confirmed recovery material in an isolated restore flow. Use synthetic data for development rehearsals. Only then offer cleanup of identified legacy plaintext files with explicit consent. Warn that deletion is not secure erasure on APFS/SSDs and cannot remove snapshots/remote copies. Do not silently delete OS backups or unrelated user exports.

Once migration has committed, normal operation must refuse plaintext for that vault. Plaintext remains a deliberate import format, not an automatic decryption fallback. If primary data is missing but migration state/backups show an existing vault, enter recovery rather than create sample data.

Do not expose a silent "disable encryption" toggle in the first release. A deliberate plaintext export remains available; any later in-place decrypt/downgrade needs a similarly reviewed workflow. Test that an old backup restored by an old app is detected by the new app's vault-state policy where state is still present. Removing/replacing all local state is outside the anti-rollback guarantee.

### Portable export and restore

- Offer **Encrypted Backup** separately from **Plaintext JSON Export**. A device-key-only ciphertext copy is not a portable backup.
- Reencrypt export data under independent export key material and the chosen export passphrase or random export recovery secret. Do not export the live VMK or a recovery capability for all future live-vault data.
- Include versioned, bounded unlock metadata needed for offline recovery. Never store the recovery secret in the same export file.
- Use the hardened private atomic export writer, but never chmod the user's chosen parent folder. Give destination/privacy warnings, and use generic suggested names rather than task titles.
- Keep plaintext JSON import/export for interoperability with explicit warnings. Decrypt and validate imports in memory, then commit under the destination vault's keys; do not adopt the source vault's identity, keys or settings implicitly. An imported file must not trigger arbitrary local Keychain lookups/prompts based on its header.
- Make full-backup restore versus existing merge-import behavior explicit, including preference handling. Verify encrypted restore on a fresh Mac/profile with no original Keychain access. Test current and older retained key generations.

## 9. Future cloud compatibility

Keep key management behind a provider interface and storage behind a repository boundary, but do not prebuild a sync protocol or upload the encrypted JSON file to a shared folder.

If provider-blind E2EE is required later, decide it **before** the server schema: per-account/device enrollment, verified key distribution, revocation/rotation, record-level authenticated payloads, tombstones/conflicts/recurrence, encrypted backups and recovery are required. Local keys must not be sent to the backend as ordinary account credentials. Cloud login/password reset must not falsely imply decryption recovery.

Server-side search, email capture, collaboration and AI may conflict with provider-blind content. Locally unlocked search can remain in memory; any future on-disk FTS/index must also be protected. File IDs, traffic volume and timing may still leak. The whole-store envelope is a local/export format, not the multi-device replication protocol. See [the product plan](CURIOS_PRODUCT_PLAN.md).

## 10. Phased implementation and acceptance gates

This table records the original proposed phases; it did not itself authorize implementation. The user later authorized the source-build vault. Actual completed scope, deliberate deferrals and verification limitations are in [ENCRYPTED_STORAGE.md](ENCRYPTED_STORAGE.md). Effort labels are relative, not schedule estimates.

| Phase | Proposed scope | Exit gate | Relative effort |
| --- | --- | --- | --- |
| A — Approve policy and prove platform assumptions | Choose near-term JSON versus imminent SQLite; threat model; KDF dependency policy; source-build route; signing/Keychain matrix; wire-format review. Only after authorization, use synthetic data and a dedicated test Keychain namespace for spikes. | A documented supported unlock/recovery route for every advertised build; reviewed format and failure-state model. | M |
| B — Implement and test the cryptographic boundary | Envelope codec, key-provider abstractions, in-memory test provider, KDF limits, ciphertext persistence, backup/export primitives and serialized transactions. | Known-answer/interoperability tests and parser tamper/fuzz/resource tests pass; no plaintext artifacts; V1 protections retained. | M–L |
| C — Build the vault lifecycle and migration | Enrollment/recovery UI, all-window lock state, draft/async handling, resumable migration, restore/export UX. | Crash/failure-injection and old-process tests; no overwrite on cancel/missing key; recovery without the original Keychain. | L |
| D — Verify real platforms and release candidate | Supported OS/hardware/signing combinations, accessibility, update/sleep/lock behavior, large-data performance, independent security review. | Recovery rehearsal, clear limitations, passing regressions, clean staged content and secret scans. No remaining critical/high findings. | M–L |
| E — Deliver reviewed source to GitHub | Publish approved source/docs/tests/CI changes to `jfeflores/Curios` through an explicitly reviewed branch/PR. | Exact diff/ref/metadata review, remote CI success and explicit release approval. | S after preceding gates |

### Required test groups

- **Crypto/format:** known-answer and independent-reader vectors, fresh nonces, wrong key/passphrase, tag/header/ciphertext tampering, truncation/trailing bytes, slot substitution, unknown versions, extreme KDF/length fields, size boundaries and Unicode passwords.
- **Integrity:** existing domain/security/application/UI regressions; unsafe symlink/hard-link/FIFO/ACL cases; short write/disk full/permission failure; stale and concurrent writers; backup corruption; previously valid primary and backup files are preserved when a write fails.
- **Migration:** normal and missing/corrupt/oversized legacy inputs, mixed-format files, old recovery naming, `DAYBOOK_DATA_DIR`, interrupted stages, key enrollment success followed by disk failure, low disk space, old binaries and repeated/resumed migration. Verify no sample-data substitution.
- **Lifecycle:** every window/command/URL/hotkey/import path while locked, unlock cancellation, lost Keychain item, authentication reuse, late callbacks, unsaved drafts, multiple windows/processes, screen lock/sleep/reboot, notification policy and VoiceOver leakage.
- **Recovery:** fresh-profile/fresh-Mac restore, wrong/missing recovery material, rotated keys, historical encrypted backup, portable export round-trip, explicit plaintext warning, destructive reset preservation and inability to reset/decrypt without credentials.
- **Artifact/performance review:** synthetic canary text absent from all encrypted primary/backup/temp/recovery/export files and logs; memory/disk/latency under worst supported data sizes. Canary scans are regression checks, not proof of cryptographic security or guaranteed memory erasure.
- **CI isolation:** fake key providers by default; unique synthetic files and test namespaces; no access to a developer's production vault/Keychain, no real recovery material in fixtures. Real Keychain and cross-machine checks are separate platform gates, not silently mocked evidence.

## 11. Eventual GitHub delivery

The approved public destination is **https://github.com/jfeflores/Curios**. Implementation can be delivered there without uploading user task data, encryption keys or investigation inputs. Publishing cryptographic source is compatible with protecting randomly generated user secrets; secrecy must not depend on hiding this code.

After separate implementation authorization:

1. Work from the reviewed public `main` on a feature branch. Keep the existing Apache-2.0 license and add required notices for selected dependencies. Review applicable cryptography/export obligations; do not assume source publication or an OS API automatically resolves every distribution requirement. Reassess App Store encryption declarations if that channel is chosen. [S12]
2. Include only intended source, synthetic tests, build/CI configuration and accurate documentation. Update README/PRIVACY/SECURITY/ROADMAP only when the claims match implemented and verified behavior.
3. Review the exact staged diff and blobs, author/committer noreply identity, selected refs and dependency/license changes. Run secret scanning on the proposed public history. Do not stage live vaults—even ciphertext—or real recovery kits, Keychain dumps, profiles with private material, screenshots, build outputs or `.analysis/`.
4. Publish only the explicitly approved branch/PR and release refs. Never use `git push --all` or `--mirror`; private legacy local refs must stay local. Leave unrelated `package-lock.json` excluded.
5. Require CI and platform/recovery review before merging/releasing. Keep source publication separate from any signed/notarized binary-distribution decision; certificates/private keys and real credentials do not belong in the repository or artifacts.

**Original planning boundary:** no commits or pushes were made during planning. Later implementation/commit authorization is separate; publication still requires explicit reviewed refs.

## 12. Decisions to approve before implementation

Recommended defaults, subject to user approval:

1. **Scope:** encrypt the complete current store, backups and recovery artifacts first; use SQLCipher instead only if the SQLite rewrite is the immediate priority.
2. **Unlock:** passphrase plus confirmed independent recovery for source/ad-hoc builds; add optional validated Keychain convenience for signed/provisioned builds. Keep user-presence enforcement distinct from simple convenience unlock.
3. **KDF:** prefer vetted Argon2id if a maintained dependency is acceptable; approve calibrated platform PBKDF2 explicitly if dependency minimization takes priority. Freeze this before shipping the portable format.
4. **Lock behavior:** explicit unlock on launch, manual/idle/session lock, no silent background capture while locked; generic scheduled reminders may still fire with disclosed metadata/staleness limits.
5. **Migration/exports:** user-consented migration and cleanup, independent recovery verification, encrypted backup as the preferred export, warned plaintext export retained. No automatic secure-erasure or E2EE claims.

## Sources

Primary documentation was consulted during planning. Platform claims still require the real-build verification gates above; no prototype or benchmark was run for this document.

- **S1:** Apple, [CryptoKit AES.GCM](https://developer.apple.com/documentation/cryptokit/aes/gcm) — authenticated encryption, nonces, sealing/opening and associated data.
- **S2:** Apple, [TN3137: On Mac keychain APIs and implementations](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains) — backend selection, access-control models and signing/provisioning differences.
- **S3:** Apple, [`kSecUseDataProtectionKeychain`](https://developer.apple.com/documentation/security/ksecusedataprotectionkeychain) — explicit data-protection selection without opting into iCloud synchronization.
- **S4:** Apple, [Sharing access to keychain items among a collection of apps](https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps) and [Restricting keychain item accessibility](https://developer.apple.com/documentation/security/restricting-keychain-item-accessibility) — access groups, accessibility and user-presence controls.
- **S5:** Apple, [`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`](https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly) — device-bound accessibility and nonmigration to another device.
- **S6:** Zetetic, [SQLCipher design](https://www.zetetic.net/sqlcipher/design/) — page encryption/authentication, journal/WAL and temporary-store requirements.
- **S7:** Zetetic, [SQLCipher Apple Community integration](https://www.zetetic.net/sqlcipher/sqlcipher-apple-community/) — package/build integration, supplying keys and verifying the encryption implementation.
- **S8:** Zetetic, [SQLCipher licenses](https://www.zetetic.net/sqlcipher/license/) — Community versus commercial terms and notices.
- **S9:** Apple Platform Security, [Volume encryption with FileVault in macOS](https://support.apple.com/guide/security/volume-encryption-with-filevault-sec4c6dc1b6e/web).
- **S10:** OWASP, [Password Storage Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html) — KDF comparison, salt/work factors and reference minimums; not a complete encryption protocol.
- **S11:** Apple, [Protecting keys with the Secure Enclave](https://developer.apple.com/documentation/security/protecting-keys-with-the-secure-enclave) — supported asymmetric-key workflow and constraints.
- **S12:** Apple, [Complying with Encryption Export Regulations](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations) — a distribution-review input, not legal advice or a source-publication exemption determination.
