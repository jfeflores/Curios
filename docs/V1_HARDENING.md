# Curios V1 hardening and verification

> Historical 1.0 source-release record. The later Curios module rename, encrypted vault and current verification are documented in [ENCRYPTED_STORAGE.md](ENCRYPTED_STORAGE.md); original 1.0 counts and internal names below remain historical evidence.

**Date:** 2026-10-25. **Scope:** local macOS source release, not a hosted-backend or notarization certification. Approved public destination: [jfeflores/Curios](https://github.com/jfeflores/Curios).

The [original audit](CURIOS_V1_SECURITY_REVIEW.md) is preserved as a historical record. Its five blockers were addressed in the current source rather than hidden by changing documentation.

## Changes and evidence

| Finding | V1 change | Regression evidence |
|---|---|---|
| C-01: permissive copies/restore | Private `0700` managed directories and `0600` staged files, backups, exports, locks and recovery files; macOS extended ACL grants removed on managed objects. Atomic rename happens after validation/write/fsync/permission work. Final symlinks, nonregular files, foreign ownership and multiple hard links are rejected. Export parents are not chmodded or stripped of ACLs. | `PersistenceSecurityTests`: umask `022`/`000`, inherited ACLs, backup/restore/export, unsafe symlinks/hard links/FIFOs, and preserved corrupt originals. |
| C-02: unreadable successful saves | Identical 64 MiB serialized limit on encode/save and decode/load. Rejected saves leave primary/backup untouched. Reads inspect descriptor size/type before allocation and reject growth/change during reading. | Serialized-framing overflow despite individually valid fields; sparse oversized input; primary/backup byte preservation; restart/round-trip tests. |
| C-03: excessive untrusted work | Indexed iterative graph validation; bounded text, assignment, collection and hierarchy sizes; bounded URL/clipboard parsing; background file read/decode for imports; validation before recurrence; period-based next-date selection and aggregate resumable catch-up accounting. | Wide 10,000-tag graph, depth boundary/cycles, UTF-8/checklist limits, invalid/out-of-range recurrence, global budget/resumption, and atomic large-project tests. |
| C-04: stale overwrites | A persistent same-inode sidecar lock coordinates processes. Each persistence instance observes file revision metadata and verifies it under the lock before replacement. Existing unobserved/externally changed files cannot be silently overwritten; reload is required. | Independent stale stores, a separate-process file change, failed capture/duplication acknowledgement, and first-writer preservation. No claim of automatic merge. |
| C-05: external writes | Both `curios` and legacy `daybook` schemes use a strict pure parser. `add` creates only an in-memory preview; identity-bound confirmation commits it. Cancellation, malformed/unknown/duplicate fields and oversized inputs write nothing; approved semantic retries are deduplicated per session. | `ExternalCaptureTests` and application checks cover both schemes, preview/cancel/approval, wrong preview identity, retries, payload boundaries and unchanged on-disk bytes after rejection. |

Additional work:

- Notifications contain constant generic text, not task/project/calendar content. A single coalescing reconciler owns OS remove/add work; the plan selects the nearest 60 future eligible reminders. Disabled/revoked permission cleanup and periodic refresh are wired; actual delivery still belongs to macOS.
- Calendar display lists are cleared on refresh when disabled or permission is absent.
- Screenshot/UI-test execution and related launch hooks are behind `DAYBOOK_DIAGNOSTICS`. The normal application build does not include the tested diagnostic literals.
- The bundle is Curios `1.0.0` / `local.curios.mac`; the executable is `Curios`. Existing Daybook schema-v1 files/data location and capture links remain compatible within the safety bounds. Internal module/target names remain Daybook/DaybookCore intentionally.
- A read-only-permission CI workflow pins the checkout action by commit and does not persist Git credentials or automatically publish releases. A remote CI result has not been claimed before pushing.

## Verification actually performed

- **69/69 domain/security tests passed**, zero assertion failures.
- **19 application integration check groups passed**, including explicit capture approval and bounded asynchronous import/recovery.
- **Two isolated native checkbox UI regressions passed** (collapsed and expanded/editor), checking visible state, persistence, Logbook and reopening.
- The normal app and explicit diagnostics/review app built successfully against the installed macOS 15.4 SDK. `codesign --verify --deep --strict` passed for the local development bundle.
- Packaging plist and shell syntax checks passed. Bundle metadata reports Curios 1.0.0.
- Normal executable inspection found none of the targeted screenshot/self-test strings (`--snapshot-state`, test-report hook, checkbox-test marker).
- SourceKit reported **0 diagnostics across 25 source/test files**.
- Reviewed **46 explicitly staged source/documentation/configuration files**, not the working folder. Gitleaks **8.30.1** reported **zero findings** for a mirror made from those exact index blobs and for existing local history. No `.analysis/`, build outputs, databases, screenshots, keys or vendor binaries are staged. The local blob/hash manifest is `.analysis/security-audit/staged-review.json`; it is not published.
- Author/committer metadata was reviewed: the original local empty commit contains a personal email address and is excluded from the approved clean release history. Public release attribution uses the account-matched GitHub noreply identity, with original local refs preserved. Passing the scans does not establish absence of all vulnerabilities.

Reproduce:

```sh
./scripts/test.sh
./scripts/build.sh
./scripts/ui-test.sh
```

Tests use synthetic temporary data; UI profiles/logs remain under ignored `.analysis/`. No normal task database or personal calendar was used. The standalone runner uses the same core test classes on this beta Command Line Tools environment. A fresh ordinary SwiftPM/XCTest run on that mismatched environment is not claimed; the CI workflow also exercises `swift test` on its Xcode runner when published.

## Important boundaries

- Data remains **plaintext**. File permissions/ACL handling are not encryption, secure erasure, an app lock, or protection against the same OS user/administrators. Parent-directory/shared-folder/OS-backup policy still matters. Export destinations and historical copies must be handled carefully.
- The cross-process protocol detects stale changes; it is not a multi-device sync engine or a guarantee against actively malicious same-user processes. If a save is rejected, preserve unsaved text and reopen/reload before editing.
- Safety ceilings are not a promise of 100k-item responsiveness. JSON snapshot saves and some view queries still perform collection-wide work. One large repeating project can consume a refresh atomically up to global data bounds; other recurrence work is deferred, not silently advanced.
- General input limits: 64 MiB serialized file/aggregate text, 1 MiB notes per item, 16 KiB title/name, 1,000 checklist entries per item, and hierarchy depth 128. URL/clipboard capture deliberately uses tighter limits. See `InputLimits.swift` and `ExternalCapture.swift` for all ceilings. Old out-of-bounds input is preserved/rejected, not silently migrated or truncated.
- Real calendar/notification permission, revocation, delivery and wider external accessibility tests remain explicit platform-verification work. No private data access or permission prompts were used to imply those tests passed.
- The development app remains **ad-hoc signed**, with no configured notarized distributor identity or production App Sandbox setup. This source release must not be presented as an Apple-reviewed/notarized binary release.
- There is **no backend, cloud API, sign-in, AI service, third-party importer or sync** to certify. Future implementations need their own privacy/security review.
- Publication setup verified public `jfeflores/Curios`, private vulnerability reporting, secret scanning/push protection, and read-only Actions defaults. Only selected reviewed release refs are published; the scripts perform no whole-folder upload or automatic push. GitHub CI results are separate from the local verification above.
