# Curios encrypted storage implementation record

This records the 1.1 source changes following [the original encryption proposal](CURIOS_ENCRYPTION_PLAN.md). It is not a third-party audit, certification, notarized binary release or cloud-E2EE claim. The independent Python format check is implementation interoperability testing, not an independent security audit.

## Implemented

- Native modules/targets/source paths are `Curios` and `CuriosCore`; tests and build/diagnostic names use Curios. The public repository was already `jfeflores/Curios`.
- New profiles require passphrase enrollment and complete independent recovery-key confirmation before task data is written. Existing legacy profiles open with a visible encryption-off label and an explicit Settings → Data migration action.
- System CryptoKit AES-256-GCM encrypts the complete validated JSON payload. A random VMK is wrapped through platform CommonCrypto PBKDF2-HMAC-SHA-256 (600,000 iterations) and an independent random recovery secret. Purpose-specific HKDF keys separate content and recovery wrapping.
- Versioned/bounded binary frames authenticate the header and body; malformed lengths, excessive KDF work, wrong credentials and tampering are rejected. Exact details are in [VAULT_FORMAT.md](VAULT_FORMAT.md).
- Primary, previous-valid backup, enrollment snapshot and known bounded recovery artifacts are encrypted. Private ACL-aware/no-follow staging, persistent sidecar locking, observed revisions and input/domain limits remain in force.
- Enrollment stages/verifies encrypted bytes, writes an encrypted `.vault` original snapshot/barrier, converts known copies and commits primary last. Partial conversions resume after explicit unlock. Unsafe/corrupt backups or oversized/excessive artifacts stop rather than being deleted or read unboundedly.
- Missing/corrupt data never silently becomes sample data. Encrypted backup restoration authenticates first and preserves current bytes; missing primary plus an existing previous backup requires an explicit recovery action.
- All main, Quick Entry and Settings content is gated by session identity. Manual and automatic sleep/session/display-lock/idle paths clear published content, history, captures, editor/search state and calendar caches. Late unlock/import/permission/editor work cannot republish the prior session.
- Manual lock warns about clearing unsaved drafts. Automatic privacy lock does not wait for prompts. Idle locking is approximately 15 minutes of Curios input inactivity, checked by the existing periodic timer. OS lock signals and multiple independent processes still have platform limitations.
- Generic already-scheduled reminders may fire while locked, but no plaintext database is retained for scheduling refresh. Timing/opaque IDs remain OS metadata and reminders can become stale until unlock.
- Encrypted portable backup uses independent key material and an export passphrase. Explicit warned plaintext JSON import/export remains available. Imports merge by ID and retain destination preferences; live keys/identity are not adopted from an import.
- FileVault is complementary: bounded, read-only `fdesetup status` plus a settings link. No enabling/disabling, administrator prompt, recovery-key collection or system-setting mutation is implemented.

## Compatibility

New default data location is `~/Library/Application Support/Curios/curios.json`. Existing Daybook profiles retain their original location/basename, lock and sidecars. A current Curios profile takes precedence if both locations exist; no automatic cross-profile merge is attempted. `CURIOS_DATA_DIR` is preferred, with `DAYBOOK_DATA_DIR` supported for compatibility. Old and new capture schemes remain registered. Notification IDs now use `curios-`, while reconciliation recognizes legacy `daybook-` IDs.

Legacy basenames deliberately do not change during encryption: old V1 then fails to decode encrypted bytes rather than treating a renamed live file as absent. Close older applications and do not use their restore function after migration. Old applications cannot enforce the new barrier; malicious deletion/replacement of every state file is not prevented by this design.

The `.vault` file is an encrypted enrollment snapshot, not a plaintext journal or an empty lock. It intentionally retains original content for recovery and supplies unlock metadata if the primary is damaged. Keep its recovery material. The `.lock` remains a persistent process-coordination file and contains no task database; never unlink it while processes run.

## Deliberate initial-release choices and limitations

- **No Keychain/Touch ID route yet.** Today's ad-hoc builds have no validated provisioned access-group identity. The supported passphrase/recovery route works without an Apple developer account; no silent legacy-Keychain fallback is shipped. Signed/provisioned convenience unlock remains a separate platform gate.
- **Platform PBKDF2 instead of a new Argon2 dependency.** This keeps application builds limited to Apple frameworks and avoids introducing an unreviewed native package. PBKDF2 is not memory-hard, not equivalent to Argon2id, and does not imply FIPS certification. Use strong unique passphrases. Future KDF changes require versioned slots and migration/interoperability tests.
- **Whole-store snapshot transactions remain synchronous.** Enrollment, password derivation, encrypted export and import decoding run away from the UI actor. Existing ordinary mutations still serialize/validate/encrypt/write complete snapshots before acknowledgment, so they can block large-data UI interactions. A transactional storage actor/SQLite redesign remains roadmap work; encryption is not a scalability claim.
- No automatic password reset, passphrase-change UI, VMK rotation, biometric enforcement, attachment encryption or cloud synchronization is advertised. Recovery can unlock without a passphrase, but cannot magically revoke old copied ciphertext.
- Portable exports expose passphrase unlock only; their independent unused random recovery secret is discarded. Do not expect the live recovery key to unlock an export.
- Existing plaintext snapshots, external copies, exports, clipboard histories and diagnostics are not securely erased. File existence/size/timestamps remain visible. Unlocked malware/OS compromise, guaranteed Swift memory erasure and malicious rollback are outside the guarantee.
- Migration bounds include at most 256 discovered legacy artifacts and a 256 MiB aggregate plaintext/copy preflight budget. A valid legacy backup must decode; opaque bounded recovery bytes can be encrypted as `recovery` content. Unconvertible inputs remain untouched for explicit remediation.
- UI regression coverage includes programmatic lifecycle invocation and real native checkbox events/readback. It does not automate typing credentials into every field, independently audit all VoiceOver surfaces, or prove every OS sleep/permission signal on every supported Mac.

## Verification

Local checks for this change:

- **83 core/domain/security tests**, including NIST AES-GCM/PBKDF2 known answers, Unicode/exact-password handling, nonce/tamper/type/length/KDF checks, 64 MiB plus ciphertext-overhead round-trip, no-write failure cases, legacy artifact migration, interrupted enrollment, missing-primary recovery, stale writers and independent exports.
- **19 existing application check groups**, plus **9 encrypted application groups**: no plaintext first-run seed, independent recovery confirmation, content/history/capture/cache locking, wrong-key preservation, recovery-only unlock, stale asynchronous unlock/import rejection, restart and authenticated corrupt-primary recovery, and FileVault parsing.
- **Three isolated native UI scenarios**: ordinary Today and editor checkbox regressions; encrypted enrollment/checkbox persistence, task-view removal on lock and recovery reopening. The encrypted scenario invokes lifecycle methods programmatically and states that limitation in its report.
- Independent Python `cryptography`/OpenSSL reader verifies Swift-produced wrapping and payload authentication through both passphrase and recovery, plus tamper rejection. Test dependencies live in an isolated virtualenv and are not application dependencies or vendored source.
- Normal/diagnostic builds and local ad-hoc signature/shell/plist validation pass. SourceKit reports zero diagnostics across 32 Swift files. Exact staged-content/secret review remains a required commit gate. Remote branch CI requires an actual push and is not inferred from local results.

Reproduce domain/application checks with `./scripts/test.sh`, native UI checks with `./scripts/ui-test.sh`, and the normal app with `./scripts/build.sh`. For independent format verification after the standalone tests:

```sh
python3 -m venv .build/interop-python
.build/interop-python/bin/python -m pip install cryptography==50.0.2 cffi==2.1.1 pycparser==3.12
CURIOS_INTEROP_PYTHON=.build/interop-python/bin/python ./scripts/interop-test.sh
```

Only use synthetic, isolated profiles. Never put live vaults, recovery keys, private screenshots, developer profiles, virtualenvs, generated apps or proprietary Ghidra/REA inputs in a commit. The README documents this project's reverse-engineering origin and independent open-source Swift direction without distributing vendor code/assets.
