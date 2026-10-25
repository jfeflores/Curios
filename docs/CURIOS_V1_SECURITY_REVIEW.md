# Curios V1 — publication, security and privacy review

> **Historical pre-hardening audit.** The findings and blocked verdict below describe the 2026-10-24 prototype, not the current source. C-01–C-05 were subsequently addressed; see [V1 hardening and current verification](V1_HARDENING.md). The original observations are retained for traceability, not erased or presented as current failures.

**Review date:** 2026-10-24 UTC.
**Target:** the current Daybook source tree proposed for publication as Curios.
**Status:** audit complete; application findings remain unresolved. No code fixes, publication, commits, staging, remote setup, or security-service configuration were performed.

## 1. Verdict

**Do not label this build a security-hardened, production-ready Curios V1 yet.** The local-data and input-handling probes reproduced privacy/availability/integrity weaknesses.

**Publishing reviewed source is a different decision from releasing a production binary.** A carefully selected source tree can be published as an experimental Apache-2.0 project after ownership/provenance, final secret scanning, staged-file review and repository reporting controls are addressed. Do not upload an archive of this entire working folder: ignored files include proprietary Things binaries, a reference image, investigation evidence, screenshots and local profiles.

No API credential was found by the checks performed. No application-owned backend, network API, login service or cloud client exists to certify. No remote-code-execution or automatic network-exfiltration path was identified in this review, but this is **not proof that every vulnerability or leak is absent**.

## 2. Scope and evidence

Reviewed source, tests, build scripts, manifest, packaging, public-candidate documentation, local Git objects/history and ignored-artifact inventory. Targeted probes used generated synthetic data in temporary directories, removed afterward; the normal Daybook data directory and personal calendars were not opened. Proprietary artifacts were identified/inventoried, not newly reverse engineered.

### Checks performed

| Check | Result |
|---|---|
| Git publication inventory before this audit's documentation changes | 33 candidate files, 294,337 bytes; all application files were untracked. No Git remote was configured. |
| Local Git history/objects | One empty initial commit; no tracked source files or unreachable blob objects found by the inventory/fsck. This does not describe any repository outside this local Git directory. |
| Local credential scan | 128 working-tree files, including ignored artifacts (103,000,468 logical bytes), excluding `.git` and this audit's own generated output. No matches from the configured credential patterns or high-entropy candidate-string check. |
| Scan patterns | Private keys; common GitHub/AWS/Google/Slack/Stripe/OpenAI/Anthropic token shapes; JWTs; credentials in URLs; common credential assignments; review of high-entropy quoted literals in candidate files. No credentials were sent for online validation or to an external scanning service. |
| Dedicated secret scanner | Downloaded official Gitleaks **8.30.1** into the ignored audit directory, verified its archive against the release's published SHA-256 checksum, and ran default-rule scans of a temporary mirror of all **38 publication candidates** and all existing Git history: **0 findings**, exit code 0 for both. No global installation or source upload. |
| Privacy metadata indicators | No email-address or absolute home-directory path indicators in the original candidate files. Such indicators existed in ignored artifacts. Existing Git author metadata uses a non-GitHub-noreply address; owner approval is needed before making that metadata public. Values are not reproduced here. |
| Dependencies | No third-party Swift package dependency in `Package.swift`. The root npm lockfile contains no packages/dependencies and appears unrelated to the Swift app. Apple/OS frameworks remain dependencies under their own terms. |
| Existing regressions, freshly rerun | **44/44 domain tests and 17/17 application checks passed.** These do not cover all security cases. |
| Configuration checks | Shell scripts passed `bash -n`; packaging plist passed `plutil -lint`. |
| Existing compiled app | `codesign` reported ad-hoc signing, no team identity, no entitlements; signature flags did not include hardened runtime. Linked libraries were DaybookCore and Apple/system libraries. This existing binary is not a notarized Curios release. |
| Targeted adversarial probes | File/restore permissions, plaintext persistence, invalid inputs, URL behavior/large payloads, stale-store overwrite, save/load size mismatch, and nested-tag validation cost. Results below. |

**Scanner limitation:** both the heuristic scan and Gitleaks are pattern-based and can miss unusual credentials or private information. Gitleaks was run on the current publication candidates and existing history; nothing was staged or committed. Re-run it on the exact final staged tree and complete history before pushing. Verifying a downloaded tool against its published checksum is an integrity check, not a comprehensive supply-chain certification. Do not mistake hashes/evidence IDs for credentials, or a clean scan for a security guarantee.

Local reproducibility artifacts are kept in ignored `.analysis/security-audit/`: `scan_repository.py`, `secret-scan.json`, `SecurityProbe.swift`, `security-probes.json`, `ValidationScaling.swift`, `validation-scaling.json`, `gitleaks-tool.json`, `gitleaks-summary.json`, redacted scanner reports, and test/probe logs. Do not publish this folder wholesale. Promote sanitized probes into normal regression tests when fixes are authorized.

## 3. Actual backend and attack surface

The current “backend” is `AppStore` + `DaybookCore` + JSON persistence on the local device. There is **no server backend**: no server routes, hosted database, Supabase/Firebase project configuration, OAuth implementation, account service, session cookies, API keys or cloud-sync protocol were found.

Consequently this review cannot certify server authentication/authorization, tenant isolation, injection resistance of a future SQL API, TLS deployment, rate limiting, storage buckets, infrastructure secrets, cloud retention or account deletion. Those systems must be designed and audited when they exist.

Current trust boundaries:

- External `daybook://` URL input reaches the app via `ContentView.swift:114` and `AppStore.swift:231–245`.
- User-selected JSON and clipboard text become tasks; persistence validates structure but input size/work boundaries are incomplete.
- Local data/backup/restore/export files are plaintext and rely on OS access control.
- Calendar permission permits an EventKit read of selected calendars; notifications hand task content to macOS.
- Build/diagnostic scripts and developer launch arguments run with the invoking user's privileges.

Source review found no application-owned network transport, listening socket, telemetry SDK, shell/process invocation using task text, SQL engine, webview or JavaScript evaluator. Markdown uses `AttributedString` in native text (`Sources/Daybook/Theme.swift:95`), not HTML script execution. This lowers several common web-style attack surfaces; it does not eliminate parser, resource, link-opening, platform or local-data risks.

## 4. Confirmed findings and release gates

Severity is contextual engineering triage, not a CVSS score or claim of remote exploitation. The application findings below were not fixed in this audit.

### C-01 — Inconsistent private permissions on sensitive local copies

**Priority:** must fix before a privacy-hardened V1; local confidentiality weakness.
**Evidence:** `Sources/DaybookCore/Persistence.swift:26–34`; `Sources/Daybook/AppStore.swift:204–207,219–228`.

With process umask `022`, the synthetic probe measured:

| Path/action | Mode |
|---|---|
| Primary after normal save | `0600` |
| Automatic previous-valid backup | `0644` |
| Created data directory | `0755` |
| JSON export using the current export write path | `0644` |
| Primary after `AppStore.restoreBackup()` | `0644` |

Both primary and backup contained the synthetic task title as readable JSON. Normal save restricts only the primary file, after its write. Backup, export and restored-primary paths do not consistently set private permissions.

**Impact qualification:** `0644` allows other OS users to read a file *if parent-directory permissions/ACLs permit traversal*. The probe did not demonstrate another user accessing a real home directory. Same-user malicious processes are not stopped by `0600`, and plaintext is not equivalent to encryption. No automatic network leak was observed.

**Acceptance:** create sensitive app-managed directories/files privately from the start; enforce owner-only modes on primary/backup/restore/recovery paths; define symlink/ACL behavior and durable commit semantics; test umask `022` and `000`, restore, failure and replacement. Exports require a clear plaintext warning and private creation defaults, while respecting a deliberate user's sharing action.

### C-02 — A successful save can produce a database the app refuses to reload

**Priority:** high data availability/integrity; V1 blocker.
**Evidence:** `Sources/DaybookCore/Persistence.swift:10–16,23–34`.

`decode` rejects files over 64 MiB. `encode`/`save` do not enforce that serialized byte ceiling. A single valid synthetic task with 64 MiB of notes produced **67,109,558 bytes**. `save` returned successfully; `load` rejected the file, and a new `AppStore` opened read-only with a load error.

This is not a demonstrated data exfiltration attack. It is a reproducible self-lockout, possible through accumulated large content. A previous-valid backup may help, but recovery must not be the normal way to reopen a successful save.

**Acceptance:** every successful save must be readable by the corresponding loader; define per-field/collection and serialized limits, enforce them before durable replacement, preserve prior valid data on rejection, and add below/at/above-boundary restart tests.

### C-03 — Untrusted input can trigger excessive allocation or UI-thread work

**Priority:** medium availability risk; V1 input-hardening blocker.
**Evidence:** `Sources/Daybook/AppStore.swift:5,36–47,190–202,231–241`; `Sources/DaybookCore/Persistence.swift:15,21,29`; `Sources/DaybookCore/Models.swift:231,239–245`; `Sources/DaybookCore/Recurrence.swift:218–236`.

- `Data(contentsOf:)` reads a whole file before `decode` checks its length. A post-allocation 64 MiB guard is not a pre-read memory limit.
- JSON decoding and nested relationship validation occur synchronously along main-actor application paths.
- Tag validation walks each tag's ancestry and repeatedly performs linear tag lookups. Deep valid chains have approximately cubic worst-case work under this implementation.
- In the current unoptimized audit build, valid tag-only JSON measured **100 tags / 13,736 bytes: 0.040 s; 200 / 27,436: 0.171 s; 400 / 54,836: 1.383 s**. These are observations on this machine, not release-build benchmarks or an extrapolated guaranteed freeze time.
- The URL handler accepted a synthetic **1 MiB notes payload** without an application-level small-payload limit. This was a direct handler probe, not a claim that every browser/Launch Services path accepts arbitrary URL sizes.
- Recurrence has a per-template generation budget, but aggregate work across many templates and worst-case next-date searching still needs adversarial testing.

**Acceptance:** bound bytes before whole-file reads, set sensible text/relationship/depth/checklist/URL limits, make validation indexed and bounded, validate before expensive recurrence work, and support off-main-thread processing/cancellation with work/time budgets. Test malformed, deeply nested, large and repeated inputs; avoid “fixing” only the UI spinner.

### C-04 — Independent stale stores silently overwrite each other's saves

**Priority:** medium data integrity; fix before claiming safe multi-process/multi-client use.
**Evidence:** `Sources/Daybook/AppStore.swift:21–24,36–47`; `Sources/DaybookCore/Persistence.swift:19–34`.

Two `AppStore` instances loaded the same synthetic file. Each added a distinct task and reported a successful save. Reloading showed the second task but **not the first**. Atomic file replacement prevents partial JSON writes; it does not prevent lost updates.

Normal windows currently share one store, which avoids this specific scenario within that instance. The probe models independently launched instances/stores; actual widgets/cloud clients do not exist yet. It is not a remote attack or evidence that normal shared windows lose writes this way.

**Acceptance:** coordinated transactional storage or explicit single-writer enforcement, stale-write detection and conflict/reload behavior. Test multiple processes, external edits, termination and recovery before adding extensions/sync.

### C-05 — URL task creation is an unauthenticated write surface

**Priority:** low-to-medium abuse/usability risk; an intentional integration requiring explicit policy.
**Evidence:** `packaging/Info.plist:16`; `Sources/Daybook/AppStore.swift:231–245`.

The same add URL invoked twice created two tasks without an in-app confirmation. A shell-looking notes payload remained literal text; no command execution was involved. Unsupported `delete` and foreign-scheme URLs were rejected without changing the database in the probes.

Other apps, launchers or websites may initiate custom-scheme navigation subject to OS/browser handling. That can cause unwanted task creation, duplicate capture and expensive repeated writes. This is not an authenticated internet API, not a CSRF finding against a nonexistent web backend, and not a demonstrated read/exfiltration endpoint.

**Acceptance:** choose capture-preview/confirmation or explicit user-enabled automation behavior, payload limits, retry/idempotency policy and write-abuse controls. Keep destructive/read-export callbacks out unless separately authenticated/designed. Don't put sensitive content in URLs; other software may log/history them. New authentication callbacks must not reuse this permissive handling pattern.

## 5. Additional privacy, release and safety observations

These are confirmed design/configuration facts or code-derived risks, not newly reproduced attacks:

- **Notifications expose task content to OS previews.** `Sources/Daybook/Integrations.swift:50` includes title and project/area name. Add a content-redaction option and accurate disclosure; verify actual macOS preview behavior. Scheduling is asynchronous remove-and-rebuild work and still needs ordering/disable/revocation tests. No unauthorized notification delivery was reproduced.
- **Calendar permission is broader than the app's behavior.** EventKit full-access permission is requested (`Integrations.swift:16–20`), but reviewed app code reads events rather than writing them. Event objects are held in memory; selected calendar IDs are persisted preferences. Permission denial/revocation and stale-cache/UI clearing remain OS test gaps.
- **Developer screenshot/test hooks ship in the current executable.** `Integrations.swift:83–98` can write an own-window screenshot to a command-line path; UI self-tests use environment-selected profiles. These require local launch control and are not proven privilege escalation. Decide compile-time exclusion or explicit production restrictions and avoid accidental task/calendar screenshots in diagnostics.
- **Post-commit errors can confuse save state.** The primary file is replaced before a throwing permission update (`Persistence.swift:33–34`), while `AppStore` updates memory only after success. A permission error could leave disk newer than the UI. Fault injection is needed; this failure was not reproduced here.
- **Restore preserves older data.** Recovery copies/backups and user exports retain content even after logical deletion. Document retention; do not promise secure erasure or app-level encryption.
- **No production binary trust configuration exists.** Current build scripts ad-hoc-sign without runtime hardening/notarization, and the app has no sandbox entitlement. This does not prevent publishing source; binary distribution needs an intentional App Store or Developer ID route and least-privilege capability review. Developer ID distribution does not inherently require App Sandbox, but the isolation trade-off must be explicit.
- **Native parsing and OS frameworks are not vulnerability-free by assumption.** No third-party package graph to audit today does not mean no platform vulnerabilities or supply-chain risks. Pin supported toolchains and review future dependencies/actions.

## 6. Publication contents and licensing

### Safe publication boundary

The original normal-Git candidate tree consisted of `.gitignore`, `Package.swift`, `README.md`, `Sources/`, `Tests/`, `docs/`, `packaging/`, `scripts/`, and an empty-dependency npm lockfile. New license/security/privacy/roadmap/audit documents are also intended source candidates. Each still needs final staged review and ownership clearance.

**Never publish as part of this release:**

- `.analysis/Things3-arm64` and `.analysis/ThingsModel-arm64`: proprietary vendor executable/framework slices.
- `.analysis/reference-today.png`: vendor/reference imagery, not an original Curios asset.
- Raw evidence/snapshots, localization extracts, logs, local profiles, app-data JSON, backups and private screenshots.
- `.build/`, `build/`, signing keys/profiles, credentials or environment files.

These artifacts were ignored and not tracked in the inspected Git state. `.gitignore` does not protect files already committed, `git add -f`, manually attached GitHub releases, browser uploads, copied folders or ZIP archives. The repository's source is currently untracked: an empty `git diff` is not evidence that publication contains nothing.

### Apache-2.0

The audit added the unmodified Apache License 2.0 text to root `LICENSE`, and README now declares that license for original project source/documentation. The standard appendix placeholders are part of the official license text, not an assertion of ASF ownership.

Before public release, the owner must confirm:

1. Who owns the original source/docs and the correct copyright attribution/year; add accurate notices/SPDX headers where appropriate without inventing a legal entity or removing existing attribution.
2. That all included material can be licensed. The source comments/docs describe an independent implementation, but code review alone cannot prove provenance, clean-room status, or legal rights in reverse-engineered work.
3. That no vendor binaries, decompiled output, artwork, copied expressive code/help text, credentials or private data are being redistributed under the project license. Retain honest history/provenance documentation rather than hiding origin.
4. Any required third-party notices. No third-party package or upstream `NOTICE` obligation was identified in the current source. A separate `NOTICE` is not automatically mandatory for every original Apache-2.0 project; preserve required notices if applicable material is added.
5. Apple SDK/framework/system-symbol use remains subject to Apple's terms; native API usage does not relicense Apple's assets. The app icon generator draws original primitives; no standalone vendor icon asset was found in the candidate tree.
6. The Curios name/branding and the applicable legal distribution questions. Apache-2.0 does not grant others' copyright, patent or trademark rights, nor does it provide non-infringement clearance.

This is engineering licensing hygiene, not a legal opinion. No claim of Apache Software Foundation sponsorship is made.

### Curios V1 identity

The current package, targets, executable, bundle ID, URL scheme and runtime paths remain **Daybook**, and `packaging/Info.plist:10` reports **0.2.0**. README/roadmap explain the planned Curios identity without pretending a runtime rename or V1 release occurred. A future rename must migrate user data and review notification identifiers, bundle permissions, URL compatibility and release signing; renaming a repository alone does not do that.

## 7. Required gates

### Before making the source public

- [ ] Confirm ownership/provenance, copyright attribution and required notices; review branding/legal concerns.
- [ ] Inspect the exact staged file list and staged content, not merely `.gitignore` or `git diff` on this currently untracked tree. Exclude prohibited artifacts and review Git author metadata.
- [ ] Re-run the dedicated, version-pinned secret scanner over the final staged content and complete history being pushed. The current 38-file candidate mirror and existing history passed Gitleaks 8.30.1; no known credential currently needs rotation from this review. Revoke any subsequently discovered real secret before publication.
- [ ] Configure a real private security reporting route; `SECURITY.md` currently describes that prerequisite rather than claiming it is live.
- [ ] Enable/verify applicable GitHub secret scanning/push protection and repository protections; future CI must use minimal token permissions, trusted/pinned actions and no secrets in untrusted pull-request jobs. These features are not configured by adding documentation.
- [ ] Present the repository as experimental with the known limitations; do not attach local application/data/debug archives as releases.

### Before calling the app production-ready Curios V1

- [ ] Resolve C-01 through C-04 and define/test the C-05 URL-capture policy.
- [ ] Add repeatable security regressions and re-audit the fixes.
- [ ] Verify OS integration privacy/delivery, failures/recovery and release diagnostic policy.
- [ ] Complete supported build/CI, appropriate signing/distribution, and safe identity/data migration.
- [ ] Publish an accurate privacy/support policy and maintain a security update process.
- [ ] Audit a future backend separately before enabling accounts/cloud/AI; this report does not approve that architecture's security.

It is reasonable to invite contributors to an explicitly experimental source release with acknowledged limitations once publication gates are satisfied. That is not equivalent to assuring users their sensitive data is already strongly protected.

## 8. Documentation-only changes during this audit

- Added `LICENSE`, `ROADMAP.md`, `SECURITY.md`, `PRIVACY.md`, and this review.
- Added ignore patterns for local credential/signing files and runtime data copies.
- Updated README for the planned Curios identity, release warning, documentation links, accurate data-copy description and Apache-2.0 declaration.
- Added local ignored audit/probe/scanner artifacts and reran existing tests. No application sources, tests, build scripts, manifest or packaging were edited; SHA-256 comparison confirmed all 24 original application/test/build/packaging/manifest files unchanged. Local documentation links were checked, and `LICENSE` matched the official Apache text ignoring boundary whitespace.

## References

- [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0.txt) and [official licensing/application FAQ](https://www.apache.org/foundation/license-faq.html#Apply-My-Software).
- [GitHub secret scanning](https://docs.github.com/code-security/secret-scanning/about-secret-scanning): pattern coverage is not a guarantee that all secrets or private data are detected.
- [GitHub private vulnerability reporting configuration](https://docs.github.com/code-security/security-advisories/working-with-repository-security-advisories/configuring-private-vulnerability-reporting-for-a-repository).
- [Public roadmap](../ROADMAP.md), [privacy notes](../PRIVACY.md), [security policy](../SECURITY.md), [product/architecture plan](DAYBOOK_PRODUCT_PLAN.md).
