# Curios roadmap

Curios V1 is the local macOS application in this repository. The product direction is a calm, original planner that helps people choose a realistic day, retain context and recover when plans change. Future features are proposals, not current capabilities or dated delivery promises.

## V1 security and data-integrity foundation

- [x] Private, ACL-aware app-managed files/directories and private atomic export/backup/recovery.
- [x] Symmetric 64 MiB save/load limits and bounded regular-file reads.
- [x] Indexed relationship/cycle validation and explicit UTF-8, collection and nesting bounds.
- [x] Aggregate recurrence work limits with resumable cursors and atomic project copies.
- [x] Cross-process sidecar locking and observed-revision checks that reject stale writes.
- [x] Strict external capture parser, user confirmation, cancellation and approved-capture deduplication.
- [x] Generic notification text, bounded due-date scheduling and serialized reconciliation.
- [x] Screenshot/UI-test hooks excluded from normal builds.
- [x] Curios 1.0.0 bundle identity, retaining legacy Daybook schema/data paths and capture links.
- [x] Domain/security/application regressions and isolated native checkbox tests; see [V1 hardening](docs/V1_HARDENING.md).
- [x] Apache-2.0 license, visible privacy/security documentation and a minimally privileged pinned-checkout CI workflow.

## Source publication gates

- [x] Review the current 46-file Git index, including modes, text contents, license/provenance notes and generated-artifact exclusions.
- [x] Scan that exact index and existing local history with Gitleaks 8.30.1 (zero findings); review author/committer privacy. Re-run after any release-commit changes.
- [x] Confirm public `jfeflores/Curios`, GitHub noreply attribution and a clean release root that excludes private local ancestry; enable and verify private vulnerability reporting and secret scanning/push protection.
- [x] Enforce source-only publication through an explicit reviewed index and selected release refs—never working-folder uploads, ignored investigation inputs, local app bundles or private data.

## Encrypted Curios source update

- [x] Rename active app/core/test modules and build/diagnostic identifiers to Curios; retain legacy profiles and capture compatibility.
- [x] New-profile enrollment, CryptoKit AES-256-GCM vault, platform PBKDF2 passphrase and independent confirmed recovery.
- [x] Encrypted managed backup/recovery/enrollment snapshot, resumable bounded legacy conversion, stale-writer and explicit missing/corrupt-primary recovery safeguards.
- [x] All-window session locking, async-generation guards, generic reminder policy and explicit unsaved-draft warnings.
- [x] Independent encrypted portable backup, explicit warned plaintext interchange, read-only complementary FileVault status/settings guidance.
- [x] Clearly document the Ghidra/Things reverse-engineering skills origin and independent, gradually evolving open-source Swift todo-app direction.

See [implementation evidence and limitations](docs/ENCRYPTED_STORAGE.md). Keychain/Touch ID, Argon2 adoption, rotation UI and a scalable transactional repository are not shipped claims.

## Remaining platform/release verification

- [ ] Broader keyboard/VoiceOver, editing, multi-window, drag/drop and external accessibility coverage.
- [ ] Real-system calendar/notification permission, revocation and delivery tests with deliberately selected test accounts.
- [ ] Remote CI results on supported Xcode versions; more property/failure-injection and stress tests.
- [ ] A deliberate signed/notarized distributor release or App Store build if binaries are distributed. Current builds are ad-hoc development builds.
- [ ] Broader signed/provisioned Keychain/Touch ID verification and independent cryptographic/security review before expanding unlock policies; current source builds use passphrase/recovery only.

## Distinct local planning experience

- Original navigation, visual system, task/date hierarchy and responsive editing layout.
- Accessible keyboard/VoiceOver flows, comfortable/compact density and useful formatting.
- Chosen daily commitments separate from the available backlog.
- Optional duration/capacity guidance and restart notes for interrupted work.
- Short, skippable onboarding with editable, understandable layout presets.

## Trustworthy migration

- Staged imports with previews, source provenance, duplicate detection, fidelity warnings and safe rollback.
- Daybook/Curios JSON is supported now. Generic CSV/text, Reminders and Todoist adapters need separate implementation and fixture verification.
- Evaluate Things and other sources through documented, user-authorized exports/APIs; no claim of lossless universal import.
- Preserve useful export so users are not locked in.

## Accounts and cloud

- Decide privacy/encryption requirements before selecting the backend.
- Optional local start, safe guest-to-account migration, account isolation, export/deletion and managed authentication.
- Transactional local storage plus one selected sync system with tested conflict/deletion/recurrence handling.
- A focused iPhone companion after the shared data boundary is reliable.

No server/backend, sign-in or synchronization is implemented in V1.

## Apple integrations

- App Intents/Siri/Shortcuts for bounded capture, find, open and complete actions.
- Share capture, widgets and optional Spotlight indexing with explicit privacy rules.
- Calendar display first; calendar writes only through a separate opt-in design.

## Later, subject to demand

Additional importers/connectors, weekly review, calendar time blocking, web/Android clients, small-group sharing, attachments and explainable scheduling assistance. Autonomous AI scheduling and enterprise project-management features are not initial-release commitments.

See [the detailed product/architecture plan](docs/CURIOS_PRODUCT_PLAN.md). Historical Daybook investigation/parity reports document the prototype's origin; visual/feature parity is not the long-term product specification.
