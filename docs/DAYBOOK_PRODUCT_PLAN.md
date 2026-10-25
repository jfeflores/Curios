# Daybook: codebase review and product plan

> Planning snapshot from before Curios V1 hardening. The subsequently authorized security/data-integrity work is recorded in [V1_HARDENING.md](V1_HARDENING.md). Broader design, cloud and integration proposals below remain roadmap items, not implemented capabilities.

**Status:** Proposal for discussion. No implementation authorized or performed.
**Reviewed:** 2026-10-24.
**Scope:** Current source, tests, packaging, existing Daybook screenshot, project documentation, and current official product/platform documentation. No Things database, account, cloud service, or additional proprietary artifact was accessed.

## 1. Recommendation

Build **a calm, local-first planner that helps people choose a realistic day, keep context, and recover when plans change**.

Keep the native speed, reliable capture, independent start/deadline dates, projects, recurrence, keyboard support, and data ownership. Stop treating Things feature parity or visual similarity as the product specification.

Three product pillars:

1. **A plan that fits:** distinguish the backlog from today's chosen commitments; make time and capacity visible without requiring calendar micromanagement.
2. **A workspace that fits:** short, optional onboarding produces understandable, editable layout defaults—not a different, unpredictable application for every person.
3. **Trust without lock-in:** offline use, dependable sync, understandable migration, recoverable changes, and useful export.

**Recommended initial audience:** individuals balancing work and personal responsibilities, especially people moving from a basic to-do list or an Apple-native task manager. This is a hypothesis to validate, not established demand. Do not start by building an enterprise project-management suite.

**Proposed first public product:** differentiated macOS experience, optional account/cloud sync, a focused iPhone companion, a small set of Siri/Shortcuts actions, guided setup, and a few excellent importers. Defer autonomous AI scheduling, broad team collaboration, and dozens of connectors.

## 2. What exists, and what the review establishes

### Strengths worth preserving

- A small native SwiftUI/AppKit app with a separate Foundation-based `DaybookCore` module; no current third-party package dependencies (`Package.swift`). The core is a useful starting point for another Apple client.
- Substantial actual functionality: capture, projects/areas/headings, tags, search, independent dates, recurrence, completion/cancellation, trash, batch edits, undo, and portable own-format JSON.
- Thoughtful data-safety behavior: validation, atomic saves, a previous-valid backup, protection against corrupt input, and field-aware editor commits.
- Concrete regressions for stale edits, destructive mixed-selection behavior, completion cascades, recurrence, and recovery.

**Fresh verification:** `./scripts/test.sh` passed **44/44 domain tests and 17/17 application integration checks**. It uses isolated temporary data. This does not establish production scalability, cloud correctness, real notification delivery, or broad UI accessibility. The existing in-process checkbox UI evidence was reviewed, not rerun. The screenshot reviewed was `.analysis/daybook-today.png`; layout recommendations are source/screenshot observations, not a new usability study.

### Production-readiness findings

Priorities below describe prerequisites for the proposed product, not claims that every risk is a reproduced bug.

| Priority | Confirmed evidence | Consequence and planned response |
|---|---|---|
| Before cloud/extensions | `Sources/Daybook/AppStore.swift:5,36–47` performs transactions on `@MainActor`; `Sources/DaybookCore/Persistence.swift:23–34` encodes the entire database and reads/validates/backups the previous file on save. | Work per mutation grows with the collection and runs on the UI actor. Move durable transactions to an isolated storage layer; keep UI publication on the main actor. Do not sync the JSON file through a shared folder. |
| Before release | `Sources/DaybookCore/Persistence.swift:33–34` replaces the primary file before a throwing permission update; `Sources/Daybook/AppStore.swift:41–47` publishes the new state only after the save returns successfully. | A post-replacement error could leave disk newer than the UI despite a reported failure. This is a code-derived edge case, not a reproduced incident. Define the durable commit boundary and fault-inject each save/recovery stage. |
| Before scale claims | `Sources/DaybookCore/Models.swift:142–155,178–260` uses array scans for relationships, queries, and validation. `Sources/Daybook/AppStore.swift:69–86` builds a presentation database and ID dictionary. | Repeated nested lookups can become quadratic. The 100,000-item validation ceiling is not a performance guarantee. Benchmark, add indexed queries, and publish view-specific results. |
| Before account support | `Sources/DaybookCore/Models.swift:136–140` describes one database; `Sources/DaybookCore/Persistence.swift:6–8` chooses one data path. | No account isolation, ownership, or account-switch lifecycle exists. Separate local-only and account-scoped stores before sign-in can upload anything. |
| Before multi-device writes | Items have UUIDs, timestamps and trash state, but no synchronization revisions/change cursor (`Sources/DaybookCore/Models.swift:69–94`). | `modifiedAt` alone is not a safe merge protocol. Add idempotent mutations, revisions, deletion retention, conflict handling, and a durable pending-write mechanism. |
| Before shared-process access | Windows share one store, but persistence loads/saves a file without a coordinated multi-process transaction model (`Sources/Daybook/AppStore.swift:21–24`; `Sources/DaybookCore/Persistence.swift:19–34`). | A widget, intent, or second process must not independently read-modify-write stale JSON. Use transactional storage and explicit cross-process change observation. |
| Before schema growth | `Sources/DaybookCore/Models.swift:230` only accepts schema version 1; synthesized Codable models are the wire/storage shape. | Optional compatibility additions exist, but there is no general migration chain. Version local schema, export format, and network protocol independently. Add fixtures and rollback-safe migrations. |
| Before synced undo | `Sources/Daybook/AppStore.swift:16–17,43,50–57` holds up to 80 database snapshots and restores entire states. | A future undo could revert unrelated incoming changes; memory also grows with snapshots. Use operation-scoped inverse actions that become new local/synced mutations. |
| Before offline recurrence sync | `Sources/DaybookCore/Recurrence.swift:218–250` deduplicates occurrences inside one database and generates a random copy UUID. | Two offline devices could independently create the same occurrence. Use a unique logical occurrence key and deterministic identity or server reconciliation, including repeating-project children. Preserve the existing recurrence rules/tests. |
| Before reliable reminders | `Sources/Daybook/Integrations.swift:39–56` launches asynchronous remove-and-rebuild notification work for updates; its `prefix(1000)` is applied before filtering actual future reminders. | Rapid edits can overlap scheduling passes, and array position is not reminder priority. Plan one serialized reconciler, nearest-due scheduling within verified OS limits, and tests for permission revocation, cancellation, launch and sleep/wake. No delivery failure was reproduced in this review. |
| Before international/mobile release | Day construction/calculation often defaults to `Calendar.current`, while ISO validation explicitly uses Gregorian (`Sources/DaybookCore/Models.swift:7–24`). Reminder data is an instant; recurrence commonly uses the executing device's calendar (`Sources/DaybookCore/Recurrence.swift:37,218`). | Define civil-date/calendar semantics, fixed-versus-floating reminder times, recurrence time zone, travel, and week-start behavior. Test non-Gregorian preferences and DST; current tests cover some Gregorian/DST cases only. |
| Before advanced concurrent edits | `Sources/DaybookCore/ItemEditing.swift:7–25` preserves live metadata and merges tag deltas, but replaces changed notes/checklists as fields. `Sources/Daybook/AppStore.swift:166–173` renumbers item positions on reorder. | Good local edit protection is not a complete multi-device merger. Preserve conflicting notes, merge checklist entries by ID, and define stable per-container ordering and tie-breaking. |
| Before migration promises | `Sources/Daybook/AppStore.swift:190–202` imports Daybook JSON and replaces matching IDs. | No third-party adapters, preview, provenance, fidelity report, or durable import session exists. Build a separate staged migration pipeline; retain legacy Daybook import compatibility. |
| Before release | `scripts/build.sh` creates an ad-hoc-signed app; `Package.swift` targets macOS only; current packaging has no extension targets or production entitlement setup. Existing documentation records a toolchain workaround and incomplete external UI/OS verification. | Establish a supported Xcode build, real app/extension targets, CI, release signing and the chosen distribution path. App Store builds need sandbox/capability design; direct distribution needs Developer ID signing, hardened runtime and notarization. |

The codebase is a credible local prototype, not a disposable mock. Refactor the storage/application boundaries incrementally; do not rewrite all domain logic or abandon native UI simply to add cloud.

## 3. Competitive lessons, not a feature-shopping list

Official sources were checked on the review date; availability can vary by platform and plan. These are observed strengths, not an exhaustive comparison or proof that competitors lack our proposed features.

| Product | Useful lesson | Daybook decision |
|---|---|---|
| Things | Calm capture and organization; separate scheduling concepts; native interactions. | Preserve the clarity, not the recognizable sidebar/icon/editor composition. |
| Todoist | Natural-language capture, broad reach, calendar layout, durations, filters, integrations. [S1] | Make entry fast and views useful; do not assume calendar planning is a unique feature. |
| TickTick | Calendar/timeline views, focus tools, habits, smart filters, and imports. [S2] | Offer optional tools progressively; do not put every productivity feature in the default layout. |
| Sunsama | Guided planning, realistic workload, timeboxing, and shutdown/review. [S3] | Planning should help choose what fits, not just present another endless list. |
| Akiflow | Integration inbox, keyboard command bar, durations, time slots, linked source content. [S4] | Preserve source context and consolidate capture; avoid building every connector at once. |
| Motion | Scheduling around priorities/deadlines/dependencies and replanning. [S5] | Explore explainable suggestions with explicit approval before autonomous rearrangement. |
| OmniFocus | Custom perspectives, review, planning/defer/due dates, flexible organization, encrypted sync. [S6] | Depth and privacy are competitive expectations; expose complexity only when useful. |

**Important correction:** importing from other task applications already exists. TickTick explicitly documents imports from Reminders, Todoist, Microsoft To Do, and others. [S2] Our differentiator should be **migration quality and transparency**, not a claim to have invented importing.

### A differentiated experience to validate

The combination, execution, and audience fit can distinguish Daybook. None of the following should be marketed as categorically unprecedented without further research:

- **Realistic Day:** choose commitments against available time, with an explicit buffer. Explain why a task is suggested and never silently change its deadline.
- **Restart Cards:** on pausing work, optionally save “where I stopped,” the next small action, and source links. When returning, show that context instead of only the original task title.
- **Recovery Planning:** when work slips, offer “split / reduce scope / choose another day / drop it,” rather than automatically growing an overdue wall. Changes are previewable and reversible.
- **Migration Receipt:** show what was preserved, transformed, omitted, and potentially duplicated; provide source links and safe rollback.

Launch with one coherent promise, not four unrelated headline systems. Prototype Realistic Day plus Restart Cards first; treat the others as supporting trust/usability work.

## 4. A visual and interaction direction that belongs to Daybook

### Information architecture

Organize around the user's questions rather than copying the original product's list taxonomy:

- **Capture:** what needs sorting?
- **Plan:** what have I chosen for this day or week?
- **Projects:** what outcomes am I moving forward?
- **Library:** backlog, saved views, reference and completed work; Trash lives here or in settings.

These labels are provisional. Keep conventional terms like Inbox/Today where testing shows they are clearer; renaming alone is not differentiation. Existing Anytime/Someday semantics can remain available under backlog filters without occupying the entire primary navigation.

Proposed wide-window concept:

```text
Navigation       Day plan                              Optional context panel
Capture          Date • 2h 30m chosen / 4h available    Calendar OR task details
Plan             Chosen commitments                   Meetings + free windows
Projects         [ ] Proposal draft   45m  Due Fri     OR selected task's notes,
Library          [ ] Call supplier    10m              checklist and source links
                 Available next                       (only when requested)
                 [ ] Other eligible tasks
                 Completed today                      Capture stays one action away
```

At narrow widths use one primary surface with a sheet/detail destination, not three squeezed columns. A context panel is optional; a calendar is not mandatory for list-oriented users.

### Concrete improvements over the current layout

1. **Keep the plan stable while editing.** Test an inspector or lightweight inline title editing against the current large expanded paper editor. Do not lose the selected row, scroll position, or keyboard focus.
2. **Separate commitments from availability.** Today should not be a visually undifferentiated mixture of due work, available work, and intentionally selected work.
3. **Make dates legible.** Show “Do Tue” versus “Due Fri”; use consistent right-aligned metadata. Color reinforces meaning but does not carry it alone. Upcoming should communicate both dates when relevant, not only the next marker.
4. **Use space purposefully.** Current content is capped at 760 points with fixed padding and a minimum 870-point window (`ContentView.swift:104,109`). Support adjustable density, readable line lengths and an optional useful side panel—not merely more empty space or more columns.
5. **Make actions discoverable without hover.** Scheduling, tags, bulk actions and moving need keyboard and visible/touch alternatives. Preserve the native checkbox reliability work.
6. **Provide immediate, honest state.** Selection, saves, pending sync, conflicts, undo and completion should be visible. Distinguish “saved on this device” from “synced.”
7. **Improve typography and notes intentionally.** Define semantic type/spacing/color tokens, comfortable and compact rows, accessible contrast, text-size support, long-title behavior, and useful Markdown/list/link formatting. Do not make a rich document editor a launch prerequisite.
8. **Use a distinct visual system.** Explore a restrained accent, original identity, new navigation composition, task/date hierarchy and focused editing behavior. Avoid reproducing the star/calendar/Anytime/Someday color sequence, paper-card styling and project-ring treatment as a package.
9. **Treat accessibility as acceptance criteria.** VoiceOver order, keyboard-only operation, contrast, reduced motion, clear labels, large text, and non-color status cues must work in both appearances.

Validate alternatives with task-based sessions: capture, organize, plan tomorrow, edit without losing context, reschedule without changing a deadline, recover deleted work, and interpret an import warning. Compare task completion, errors and user understanding—not only visual preference.

**Brand/IP checkpoint:** review original-code/asset provenance, dependency licenses, distribution of investigation artifacts, App Store copycat guidance, and trademark/name availability (including “Daybook”) with qualified advice before launch. This review is not legal clearance. Apple's guideline 4.1 makes differentiation a release concern, not just a cosmetic preference. [S18]

## 5. Sign-in, onboarding, and personalization

### Recommended first-run flow

1. Explain the benefit in one screen: capture quickly, choose a realistic day, keep your data.
2. Offer **Start on this device** or **Sign in to sync**. Support guest-to-account migration with an explicit preview. If the business later requires an account, validate that choice rather than hiding it in onboarding.
3. Offer **Import existing tasks**, **Set up my workspace**, or **Start empty**. An experienced importer should not have to answer a questionnaire first. Sample content is optional and easily removable; current unconditional sample seeding is not the desired production onboarding.
4. Ask at most 4–5 short, skippable questions; show the resulting workspace preview and allow edits.
5. Help the user capture or select a first real task. Ask for calendar/notification permission only when the corresponding benefit is requested.

### Questions must map to visible defaults

| Question | Initial personalization |
|---|---|
| “What are you organizing: work, personal life, study, or a mix?” | Offer editable starter areas/projects; do not silently create a large template hierarchy. |
| “Do you prefer a simple list, a daily plan, or a calendar?” | Set the default landing surface and whether the context panel is open. |
| “What makes planning difficult: too many tasks, forgetting, estimating time, or restarting?” | Suggest capacity hints, reminders, duration chips, or Restart Cards; explain the mapping. |
| “When do you usually plan and work?” | Optional availability windows and review cadence; support irregular schedules and skipping. |
| “How much guidance and detail do you want?” | Guided/manual mode and comfortable/compact density. Accessibility settings remain independently available. |

Keep a small, consistent set of presets rather than arbitrary per-user UI generation. Store a versioned planning profile and explicit layout choices. Let people change/reset them anytime; learning may suggest changes but must not rearrange navigation without approval. Do not request diagnoses, infer sensitive traits, or upload task contents to personalize a layout.

### Account lifecycle is part of the feature

Recommended starting authentication: **Sign in with Apple plus an email one-time-code flow** through a managed auth provider. Evaluate passkeys after the core lifecycle works; avoid owning password infrastructure unnecessarily. Adding Google login later invokes an additional App Store policy review. Guideline 4.8 has specific privacy-equivalent login requirements when third-party login is used for the primary account; it is not a blanket demand that every app have Apple login. [S18]

Plan for:

- Stable provider subject/account IDs; do not identify or auto-link people solely by email, including Apple relay addresses.
- Verified account linking, recovery, revoked sessions, changed Apple identity/credentials, expired tokens, canceled login, and offline operation.
- Native authentication sessions and PKCE for browser OAuth flows, state/nonce validation as applicable, strict callback validation, and Keychain token storage. Use provider-supported native Apple token exchange where appropriate. [S14]
- A clear sign-out choice for pending edits and local data; never merge one account's cache into another account. Account switching must also clear widget/search/notification exposure.
- Export and in-app account deletion, including connector revocation, deletion status, retention policy and backup-expiry handling. App Store account-creation apps must allow initiating deletion in the app. [S19]
- Billing entitlement/recovery design if cloud is paid; expired subscriptions must not trap local data or exports.

## 6. Cloud and application architecture

### Separate three meanings of “cloud”

1. **Daybook synchronization:** Daybook data across the user's devices.
2. **Connected services:** calendars, Reminders, email and external task sources.
3. **Cloud computation:** future scheduling assistance, inbound email, or collaboration.

They have different permissions, failure modes, and costs. A calendar shown through EventKit is not Daybook cloud sync. Signing in does not automatically synchronize local data.

### Backend decision

| Route | Best fit | Trade-off |
|---|---|---|
| CloudKit + CKSyncEngine | A deliberately Apple-only personal app using the user's iCloud identity. | Reduces sync plumbing, but still requires local storage, conflict handling and account-change behavior. iCloud identity is not a separate Daybook account. Web is possible through CloudKit APIs, but independent accounts, Android and service-side workflows are less natural. [S12] |
| Managed Postgres/auth (e.g. Supabase) + a proven offline sync layer | Independent Daybook accounts and future non-Apple clients/service integrations. | More operational ownership and another sync dependency or significant custom sync engineering. Auth and Realtime alone are not a complete offline replication protocol. [S13–S15] |
| Fully custom auth/storage/sync service | Specialized requirements proven to outweigh the cost. | Largest security, correctness and maintenance burden; not recommended for the first release. |

**Provisional recommendation:** managed Postgres/auth with SQLite on the device, evaluating an established Swift-capable sync layer such as PowerSync before choosing the storage wrapper. This better matches the requested account system and potential expansion. If research confirms an Apple-only product and minimal server features, choose CloudKit instead. **Ship one sync backend initially, not both.**

This is not a final dependency selection. Verify current macOS/iOS SDK support, schema migration, background behavior, extension access, conflict hooks, licensing, hosting region, export/exit strategy and total cost. PowerSync's replication filters and upload authorization are separate concerns; database RLS must not be assumed to secure every download path automatically. Its GRDB integration is documented as alpha at review time—do not casually combine it with a GRDB-first design. [S15–S16]

### Proposed boundaries

```text
macOS UI / future iOS UI / App Intents / extensions
                    |
         shared application commands + queries
                    |
         existing domain rules, evolved incrementally
                    |
       transactional local repository (SQLite)
                    |
        durable pending changes + sync adapter
                    |
       account-authorized backend + Postgres
```

- Keep recurrence, validation and field-aware editing in `DaybookCore`; introduce explicit application commands reusable outside SwiftUI.
- Evolve `AppStore` into UI-facing state rather than the owner of disk I/O, file panels, notifications, authentication, sync and every business operation.
- Evaluate SQLite access options together with the sync choice. GRDB is one candidate for direct SQLite control; Core Data/SwiftData plus CloudKit is an alternative if the Apple-only route wins. Do not layer multiple persistence systems without a reason.
- Use a storage actor/serialized transaction boundary. A local write and its pending-sync record must commit together. Acknowledge local durability before reporting “saved”; do not await the network to complete a checkbox action.
- Use indexed destination queries, pagination/lazy rendering, search indexing and targeted UI invalidation rather than rebuilding a global database for every view.
- Use app-group storage only where required by actual extension targets, with coordinated transactions and cross-process observation. An App Intent can live in the app; it does not inherently require a separate extension.
- Keep independent versioning for schema, sync protocol and portable export. Retain a supported migration from current Daybook v1 files, preserving IDs and originals.

### Data additions to plan, not implement yet

- Account/owner identity on synced records; device registration and per-account sync state.
- Revisions, mutation/idempotency IDs, deletion tombstones, source provenance, import sessions and compact change history.
- Explicit separation of `availableOn`, chosen planning day, deadline, and optional **time blocks**. A start date is not necessarily a commitment; a time block is not a deadline. Map today's v1 `start` semantics explicitly during migration rather than guessing intent.
- Optional duration estimate, priority, context/energy tags, and saved views. Avoid making every field mandatory.
- Checklist entry identity/revisions; recurrence identity and unique occurrence keys; consistent project-child handling.
- Planning profile and intentional cross-device layout preferences; keep local calendar identifiers, OS permission state, window size, tokens and delivery state device-local.
- Task source links and optional restart notes. Attachments and collaborative entities remain separate later capabilities.

### Minimum sync contract

1. Write locally, persist an outbox/pending change atomically, and retry safely after termination or network loss.
2. Validate authorization and schema on every server mutation. Enforce tenant isolation in database policy and any replication service; never ship privileged backend keys in clients. [S13]
3. Use idempotency and acknowledged server revisions; handle duplicate, delayed and out-of-order operations. Persist inbound cursors with applied changes; support full reconciliation when a cursor expires.
4. Merge non-overlapping field edits. Preserve both versions of conflicting notes; merge checklist changes by stable entry identity. Do not silently replace an entire task with the newest device timestamp.
5. Define concurrent complete/reopen and move/reorder semantics. Start with deterministic documented rules; retain activity/version recovery. A full general-purpose CRDT is not automatically necessary.
6. Retain deletion tombstones long enough for offline devices. Define expiry and full-resync behavior so an old device cannot resurrect purged data. A remote edit does not implicitly restore a deleted task.
7. Enforce one logical recurring occurrence across devices and deterministic/canonical child identities. Decide missed-occurrence catch-up behavior and recurrence time zone; don't accidentally generate duplicate years of backlog.
8. Make undo a new scoped mutation, not restoration of an old whole-database state.
9. Expose local save status, pending uploads, last sync, retry state, account problems and resolvable conflicts. Do not promise instantaneous background sync when the OS controls execution.
10. Treat sync as replication, **not backup**. Keep versioned recovery/export and test restoring server backups independently.

### Privacy and encryption decision gate

Choose the threat model **before** committing the cloud schema. Proposed baseline, subject to approval: TLS, managed encryption at rest, least-privilege backend access, secure local/token handling, and no task content in telemetry. This is **not end-to-end encryption** and must never be advertised as such.

If provider-blind task storage is a product requirement, design E2EE, device-key enrollment, recovery, revocation, encrypted backups and metadata leakage now. It materially affects server-side search, email capture, collaboration and AI. Do not assume E2EE can be added later as a settings toggle. OmniFocus already advertises encrypted sync, so privacy is a real product comparison point. [S6]

## 7. Siri and other integrations

### Siri/Shortcuts: a bounded first version

Use **App Intents**, `AppEntity` queries, and `AppShortcutsProvider`. The framework starts at iOS 16/macOS 13; individual newer APIs have later requirements. Daybook's macOS 14 baseline does not itself block the core integration. Siri on iPhone requires an iPhone app—it cannot be supplied solely by this Mac executable. [S11]

Start with:

- Add a task to Inbox, optionally with project/date/deadline.
- Find tasks or open today's plan/project.
- Complete a specifically selected task, with disambiguation when needed.
- Start a supported focus/planning action once that feature exists.

Actions call the same application commands as the UI, work locally where feasible, and report success only after durable storage. Register and localize supported phrases; don't promise arbitrary conversational understanding. Keep task lookup account-scoped, handle locked-device privacy and authentication policy, and confirm destructive/bulk actions. Shortcut retries and ambiguous matches need testing.

Test metadata discovery, permissions, app closed/open, offline use, duplicate titles, date interpretation, multiple locales, device lock, sign-out, and real-device Siri behavior. The build must include App Intents metadata processing; simply importing the framework into the current direct-compiler script is not the complete integration.

### Sequence other integrations by leverage

| Stage | Integration | Boundary |
|---|---|---|
| First | Harden EventKit display and local notifications; add Reminders import. | Separate permission requests, explicit selection and denial/revocation behavior. EventKit Reminders permission is full read/write even if Daybook's importer intentionally performs reads only. [S10] |
| First companion | Share extension, useful widgets, Spotlight, App Intents. | Reuse shared commands/storage; define data visibility on locked devices. Widgets must not corrupt data or pretend stale information is fresh. |
| Next | Optional calendar time-block publication. | Use a dedicated Daybook calendar and linked block records. Preview writes; never move meetings or mirror every task without consent. |
| Next | Google/Outlook calendars where direct APIs add value beyond EventKit. | Avoid duplicate accounts/events; budget OAuth verification, refresh-token handling, rate limits and provider review. Keep a clear source of truth. |
| Later | Browser/share capture, email-to-task, selected Slack/Teams/Jira connectors. | Opt-in, least privilege, source links, safe content handling. Inbound email requires spam/abuse controls and quotas. |
| Later | Public API/webhooks, automation services, Watch. | Stable authenticated contracts and platform maintenance, not a shortcut around the sync foundation. |

For any continuing connector, define directionality, ownership, deduplication and what edits/completion mean in each system. Import, one-way linked capture and two-way sync are three separate products.

## 8. Importing from other applications

### Import sources and realistic fidelity

Support user-authorized exports and documented APIs. Do not scrape cloud sessions, collect another app's password, or silently inspect its live private database.

| Source | Proposed route | Fidelity/constraints to communicate |
|---|---|---|
| Existing Daybook | Current versioned JSON. | Preserve current IDs and support old exports as schemas evolve. |
| Generic tools | CSV column mapping and plain-text/Markdown lists. | Preview encoding, date locale and hierarchy. A task's title is not a reliable duplicate key. |
| Apple Reminders | Selected lists through EventKit with explicit consent. [S10] | Inspect actual exposed fields and test recurrence, subtasks, flags, completion, time zones and shared-list behavior. Do not promise access to every Reminders-specific feature. No writes/deletes to the source in migration mode. |
| Todoist | Project CSV first; authorized API if later justified. [S7] | Current CSV includes descriptions, scheduling/deadlines, duration and other fields; standard project export omits completed tasks and loses recurring start anchors. The alternative Google Sheets export has different omissions—do not confuse it with the standard CSV. Validate fixtures rather than assuming complete round-trip fidelity. |
| Things | User-run Shortcuts export or read-only use of documented Mac AppleScript capabilities. [S8] | AppleScript has documented gaps, notably around features such as headings/checklists; Shortcuts may expose more. Check recurrence/start dates explicitly. Do not advertise a lossless importer before a field audit and versioned fixture tests. The vendor documents a user-created database copy as another export route; a separate opt-in offline-file adapter could be investigated later, never against the live database and never as a requirement for launch. |
| TickTick | User-generated backup from its web interface. [S2] | Obtain consented/synthetic sample backups and verify actual format/version/field coverage; public help confirms backup/import workflows, not a stable universal interchange contract. |
| Trello | Board JSON export. [S9] | Map board → project, list → section/state, card → task, checklist → checklist. Standard board JSON includes only the 1,000 most recent actions; attachments can be links rather than files. Do not mistake a workflow column for a completion status automatically. |
| Notion | Markdown & CSV export, including linked page files where supplied. [S17] | User maps arbitrary database properties to tasks. Views, relations, formulas and page content are not equivalent to Daybook's model; preserve useful originals and report unmapped content. API integration is a separate later option. |
| Microsoft To Do | Microsoft Graph with delegated, least-privilege read access for this user. [S20] | Fetch lists/tasks/checklists with pagination and account consent. Verify field/scopes for supported accounts; enterprise policies may block access. The API also supports application permissions, but those are not needed for a personal importer. |
| Other requested tools | Prioritize from actual migration demand; e.g. Asana or OmniFocus. | Confirm documented export/API options before promising support. |

Suggested launch order: existing Daybook + generic CSV/text, then Reminders and Todoist. Evaluate a bounded Things importer early with prospective switchers; graduate it to launch support only if its honest fidelity meets user needs. TickTick/Trello/Notion/Microsoft follow demand rather than all becoming launch blockers.

### The migration pipeline

```text
Choose source/file → parse in isolation → normalize staging records
→ map fields/dates/hierarchy → detect duplicates and unsupported features
→ preview counts + representative tasks + warnings
→ explicit consent → transactional or resumable-batch import
→ persistent migration receipt + safe rollback
```

Requirements:

- Preserve source application, source collection/account namespace, original item ID where available, format version, import session and mapping decisions.
- Use source IDs for repeat-import idempotency. Where files lack stable IDs, use conservative fingerprints and ask about uncertain matches. Re-import must not overwrite subsequent Daybook edits without a conflict policy.
- Respect semantic differences: due versus do dates, subtasks versus checklists, archived versus completed, canceled versus deleted, recurrence templates versus generated copies, and assignees versus personal ownership.
- Stage everything before making changes. Count created/transformed/skipped/conflicting records and show specific examples of lost fidelity. Unsupported recurrence must not silently become an incorrect repeating rule; preserve its original description and offer an explicit conversion.
- Preserve recoverable original information locally with a clear retention choice; do not automatically upload the raw source export or fetch remote attachments.
- Set byte/row/text/decompression limits; block path traversal in archives, unsafe links/content, spreadsheet formula hazards in exports, and credential leakage in logs. Import user data as data, never as executable instructions.
- Large jobs need bounded memory, progress, cancellation, crash recovery and retry checkpoints. Don't bypass the normal save limits by constructing an oversized final database.
- Rollback removes untouched imported records and reverses eligible changes from that session; preserve or ask about records subsequently edited/synced. A whole-store restore must not erase unrelated work.
- Test every advertised source against synthetic or explicitly consented fixtures, including Unicode, time zones, malformed rows, hierarchy, recurrence, repeat import and partial failure.

**Better promise:** “Move your work with a clear account of what came across,” not “lossless import from every app.” Keep Daybook's own JSON export and a useful human-readable CSV/Markdown exit route.

## 9. Scaling beyond the prototype

### Local data and responsiveness

- Benchmark 1k, 10k, then 100k records, including completed history, long notes, tags and recurrence trees. Measure p50/p95 startup, list navigation, search, completion, memory and import throughput on an agreed reference Mac/iPhone.
- Initial proposed budgets, not current measurements: p95 local save acknowledgement and common list switching under 100 ms at 10k records; search results under 200 ms after debounce. Establish memory/startup budgets from baseline measurements. Treat 100k as a stress tier until explicitly supported.
- Add indexes/FTS and lazy/paged rendering where measurements justify them. Remove synchronous full snapshots from the hot path and bound undo/history/recurrence work.
- Test disk-full, interrupted transactions, damaged files, failed migrations, app termination, sleep/wake, clock/calendar changes, and backup restoration.

### Cloud users and operations

- Start with one well-observed backend/region, indexed owner-scoped queries, connection pooling, bounded delta batches, per-account quotas and backpressure. Avoid microservices or multi-region writes before evidence demands them.
- Realtime/push should signal new work; durable reconciliation remains the correctness path. Use retry backoff and jitter, cursor expiry/rebuild policies and stable pagination.
- Isolate imports, attachment processing and inbound mail in jobs as they are introduced; a large migration must not monopolize normal sync.
- Before release, test authorization between two accounts and every data path, backup restore, incident recovery, deletion propagation, token revocation, and load under a large import burst.
- Observe sync lag/error rate, queue depth, database query latency, storage growth and crashes without collecting task text. Provide opt-in, redacted diagnostic export.
- Build cost scenarios for 100/1,000/10,000 active accounts using measured tasks/account, edits/day, devices/account, replication egress, backups and any email/AI usage. Set spend alerts/quotas. Vendor pricing and workload are not yet sufficient for an honest dollar forecast.

### Development and release scale

- Supported Xcode version, reproducible targets, automated tests/CI, test fixtures, documented architecture decisions and separate development/staging/production environments.
- Future target organization: core domain, application commands, persistence/sync, platform integrations, then platform UI/extension targets. Split modules when they enforce a useful boundary, not to create an elaborate framework.
- Controlled schema/API compatibility across app versions, migration rehearsal and feature flags for risky connectors. Never run destructive migrations against production merely because a new app launched.
- Release signing, privacy disclosures, dependency/license review, support/recovery playbooks, crash monitoring, security review and an update/subscription strategy appropriate to the distribution channel.

## 10. Prioritized roadmap and gates

Effort is relative: S = bounded, M = multi-component, L = substantial subsystem, XL = cross-client/service program. These are not calendar commitments; staffing, validation and the sync/privacy decision are still unknown.

| Phase | Scope | Effort | Exit gate |
|---|---|---|---|
| 0 — Product/design decisions | Interview prospective users/switchers; inventory current flows; compare 2–3 original layout prototypes; define initial audience, platform scope, privacy, cloud route, migration fidelity and business assumptions. | M | Users understand the new plan/backlog/date model; one scoped launch specification and architecture decision record are approved. |
| 1 — Durable local foundation | Supported Xcode/CI; migration-safe transactional storage; command/query boundary; scoped undo; reminder reconciliation; baseline performance and accessibility coverage. Keep current features working. | L | v1 data migrates without loss; forced failure/recovery tests pass; existing regressions remain green; no whole-file write on the interactive hot path. |
| 2 — Distinct local beta | New navigation/design system; short editable onboarding; chosen daily plan; optional duration/capacity hints; first Restart Card prototype; staged Daybook/CSV/Reminders/Todoist import as validated. | L | Users can capture/plan/edit/recover without explanation; imports have accurate receipts/re-import behavior; accessibility and narrow-window flows pass. No cloud marketing yet. |
| 3 — Account and sync alpha | Auth lifecycle and account isolation; selected sync stack; revisions/deletion/conflict rules; Mac sync plus a deliberately small iPhone client for capture, plan viewing/editing and completion. | XL | Two devices converge after offline edits, duplicate delivery, recurrence races, delete/edit conflicts, token expiry and sign-out. Cross-account access is denied. Backup recovery is rehearsed. |
| 4 — Apple ecosystem/public beta | Siri/Shortcuts action set, share capture and limited widgets; real-device notification/calendar verification; safe import pilot for Things or another high-demand source. Design/quality polish. | L | Intent retry/disambiguation/privacy tests pass; stale extension data is handled honestly; signing/privacy/account deletion/support flows are ready. Scope widgets/share separately if needed. |
| 5 — Evidence-led expansion | Better weekly planning/review, optional calendar publishing, explainable recovery suggestions, additional importers/connectors, richer saved views. | M–L per feature | Retention/usability feedback supports the feature and its ongoing maintenance cost. |
| Later — Deliberate new product areas | Web/Android, small-group sharing, dependencies, attachments, public API, autonomous scheduling/AI. | L–XL each | Clear audience/business case, permissions/privacy design and capacity to operate the additional surface. |

Phases 0–1 precede risky implementation. Design research can run alongside later foundation work; integrations depend on shared storage/commands, not necessarily on cloud. Move App Intents earlier if Mac automation is the validated acquisition wedge. Do not wait for a desktop-equivalent iPhone app to validate sync, but ship no client that cannot safely preserve fields it does not edit.

### Explicit launch deferrals

- Reproducing every Things shortcut, animation, list, or rich editor behavior.
- Enterprise roles/teams, chat, Gantt charts, custom workflow builders and full document editing.
- Background autonomous rescheduling or AI access to everyone's tasks by default.
- Dozens of importers or two-way connectors before the first ones are trustworthy.
- Simultaneous CloudKit and independent-backend sync; a fully custom authentication service.

## 11. Success measures and decisions to approve

Measure outcomes with opt-in, privacy-conscious instrumentation and interviews; do not collect task contents to count feature usage.

- **Activation:** time to first useful task and first realistic plan; onboarding skip/abandonment and import completion.
- **Usability:** planning/editing/capture task completion, mistakes around do/due dates, keyboard/VoiceOver success, and perceived effort.
- **Trust:** migration warnings understood, duplicate incidence, restore success, conflicts, lost-data reports, reminder correctness and sync convergence.
- **Product value:** repeated use of chosen plans/restart context, week-over-week retention, whether users feel less overwhelmed, and willingness to pay. Do not optimize task counts or streaks as proxies for well-being.
- **Operations:** crash-free sessions, local latency, pending-write age, error/retry rates, cost per active account and support burden.

### Recommended defaults, subject to approval

1. **Audience:** personal planning first; not team project management.
2. **Platforms:** macOS first, focused iPhone companion next; preserve a path to web/Android without committing to their launch.
3. **Accounts/cloud:** optional local start; independent account/backend as provisional preference. CloudKit wins if the product is explicitly Apple-only and service-light.
4. **Privacy:** no content telemetry or AI by default; decide whether E2EE is mandatory before selecting the sync/data design.
5. **Design:** a stable, adaptive planning workspace with editable presets, not AI-generated per-user navigation.
6. **Migration:** few verified importers with receipts/rollback; no unsupported “lossless from everything” promise.
7. **Business:** test paid sync/sustainable subscription or another recurring-revenue model against ongoing operating costs. Keep data access/export independent of subscription state. No pricing recommendation yet.

**Next planning deliverables:** an approved one-page product brief, key-flow wireframes, a data/date semantics map, a cloud/privacy architecture decision, a migration fidelity matrix using consented fixtures, and a phase-1 acceptance checklist. These remain planning work; code changes require a separate go-ahead.

## Sources

Official documentation/product pages reviewed on 2026-10-24. Marketing feature claims are evidence of offered capabilities, not independently measured quality. Recheck API availability, terms, SDK status and App Store policy before implementation.

- **S1 — Todoist:** [Calendar layout](https://www.todoist.com/help/todoist/features/use-the-calendar-layout-in-todoist-lPHRQTu0o), [task duration](https://www.todoist.com/help/todoist/features/set-a-task-duration-L1kYkZv8d).
- **S2 — TickTick:** [Features](https://ticktick.com/features), [Backup & Import / imports from other apps](https://help.ticktick.com/articles/7055781405648748544).
- **S3 — Sunsama:** [Planning, timeboxing, workload, focus and shutdown](https://www.sunsama.com/).
- **S4 — Akiflow:** [Features](https://akiflow.com/features).
- **S5 — Motion:** [AI task manager](https://www.usemotion.com/features/ai-task-manager.html).
- **S6 — OmniFocus:** [Official feature matrix](https://www.omnigroup.com/omnifocus/specs/).
- **S7 — Todoist:** [Actual CSV schema, export and limitations](https://www.todoist.com/help/articles/import-or-export-a-project-as-a-csv-file-in-todoist-YC8YvN).
- **S8 — Things:** [Exporting your data](https://culturedcode.com/things/support/articles/2982272/), [AppleScript commands and documented limitations](https://culturedcode.com/things/support/articles/4562654/).
- **S9 — Trello:** [Export formats, comments and attachments](https://support.atlassian.com/trello/docs/exporting-data-from-trello/).
- **S10 — Apple:** [EventKit Reminders access](https://developer.apple.com/documentation/eventkit/ekeventstore/requestfullaccesstoreminders(completion:)).
- **S11 — Apple:** [App Intents](https://developer.apple.com/documentation/appintents), [App Shortcuts](https://developer.apple.com/documentation/appintents/app-shortcuts).
- **S12 — Apple:** [Sync to iCloud with CKSyncEngine](https://developer.apple.com/videos/play/wwdc2023/10188/).
- **S13 — Supabase:** [Row Level Security and policy tests](https://supabase.com/docs/guides/database/postgres/row-level-security).
- **S14 — Supabase:** [PKCE flow](https://supabase.com/docs/guides/auth/sessions/pkce-flow).
- **S15 — Supabase:** [PowerSync integration: local SQLite, upload queue and backend reconciliation](https://supabase.com/partners/catalog/powersync).
- **S16 — PowerSync:** [Swift SDK](https://docs.powersync.com/client-sdks/reference/swift), [GRDB integration status](https://docs.powersync.com/client-sdks/orms/swift/grdb), [RLS and Sync Streams](https://docs.powersync.com/integrations/supabase/rls-and-sync-streams).
- **S17 — Notion:** [Export formats and workspace limits](https://www.notion.com/help/export-your-content).
- **S18 — Apple:** [App Review Guidelines: copycats and login services](https://developer.apple.com/app-store/review/guidelines/).
- **S19 — Apple:** [Account deletion requirements](https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion/).
- **S20 — Microsoft:** [Microsoft Graph To Do resources and access](https://learn.microsoft.com/en-us/graph/api/resources/todo-overview?view=graph-rest-1.0).
