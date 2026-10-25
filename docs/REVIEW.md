# Code review and checkbox follow-up

> Historical Daybook checkbox review. Subsequent Curios V1 security/data-integrity fixes and current results are in [V1_HARDENING.md](V1_HARDENING.md).

## Fixed

| Priority | Finding | Fix / regression evidence |
|---|---|---|
| P1 | The completion control lived inside both whole-row selection gestures and a whole-row drag region. Unit tests only exercised the store, not the click target. | Replaced the custom-painted button with a real AppKit checkbox, isolated row gestures/dragging to the text region, and added an in-process mouse-down/up test with control and disk readback. |
| P1 | The expanded editor's square was only an image, with no completion action. | Added a native checkbox to the editor, commit-before-complete behavior and focused-editor command routing. A second native mouse regression verifies the expanded path. |
| P1 | Closing an editor replayed a stale whole-item snapshot, potentially reopening completed work, reverting other-window edits or resurrecting a removed record. | Merge only changed editable fields into the current record. Preserve live status/trash/ordering/repetition identity; never recreate a removed existing item. Core and store regression tests cover the failure modes. |
| P1 | Completed tasks left Today immediately, so there was no visible acknowledgement even when persistence worked. | Brief, token-scoped checkmark feedback without delaying persistence/Logbook. Added an optional setting to keep today's finished items visible until the day ends. |
| P1 | Opening/dismissing a mixed batch tag picker could replace all tags with their common intersection, silently stripping unique tags. | Pure `TagSelectionEdit` tracks touched tags and patches additions/removals only. Mixed tags show “Some”. Dismissal without edits is a no-op. |
| P1 | Batch date popovers wrote the first item's date/reminder fields on dismissal, even without a user choice. | Pickers now emit an explicit `DateEdit` intent only on an applied action. Date-only changes preserve each task's own reminder time; deadline edits do not alter scheduling fields. |
| P1 | Batch completion iterated an unordered set and derived each next action after parent cascades. A selected child could get reopened by the same “complete all” operation. | Capture one batch intent from the pre-edit selection; apply a deterministic parent-first order; identical status assignments are idempotent. |
| P2 | Reopening one task could strand it inside a completed project/heading, making it unavailable outside that list. | Reopen its containers without reopening unrelated completed siblings. |
| P2 | Group reopening relied solely on timestamps that ISO-8601 persistence truncates to seconds. Earlier work in the same second could be reopened incorrectly. | Optional, backwards-compatible completion-group UUIDs identify exactly which children were completed together in new operations. Legacy files remain readable; records completed before this fix still need the old timestamp fallback because lost subsecond information cannot be recovered. |
| P2 | Keyboard completion could modify a trashed record even though the pointer control was disabled. | Reject status changes to trashed records in the domain layer. |
| P2 | Tag filtering derived its available tag bar from already-filtered items. Other filters disappeared, making AND filtering unnecessarily difficult. | Derive the tag bar from the unfiltered view; apply selection separately. |
| P2 | Plain Space could be intercepted as “new task” while a native control had focus. | Route native control input to the control rather than the list shortcut monitor. |
| P2 | The custom build path's completion message still pointed to the default app. | Build output now prints the actual app path. |

The original gesture interception was identified as a code-level risk consistent with the report, not retrospectively claimed as an externally recorded failing click. The new control's click/completion/reopen path **is** exercised and verified.

## Added capabilities

- Custom tag shortcuts: Control-letter/number applies/removes the tag on the selection; Control-Option-letter/number toggles its filter. They are editable in Tags, case-insensitive, unique, and ignored while editing text. The domain/dispatch model is tested; external keyboard delivery remains unverified.
- “Keep today's finished items visible” preference. This is presentation only: completion still persists and enters Logbook immediately.
- Isolated review builds and reproducible native checkbox regressions for **both collapsed and expanded tasks** via `scripts/ui-test.sh`.
- Field-aware editor commits and context-aware completion commands, rather than stale full-record replacement.

## Further native investigation

REA 6.7.0 / Ghidra 12.1.4 analyzed the same hash-identified ARM64 ThingsModel slice. New evidence is retained separately in `.analysis/ThingsModel-completion-evidence.json` (four records), and the native session was closed after export.

- `ev_095b3dc6ad6289f1e4d7ec03e320570b8b2c9fc4ab758571030b8c783a6afc25`, **`0xe00a8`**: the status description getter branches to **0=open, 2=canceled, 3=completed**, decoded from Swift small strings. Daybook deliberately uses its own string-valued format rather than adopting the vendor's binary protocol.
- `ev_0a91c8ae800d169592c5bce763925bd9bb43f1e683304c54c359dc6066a22948`, **`0xf9e08`**: the public task setter forwards status and an `adjustingStatusOfRelatedEntities` flag into a store-bound entity setter.
- `ev_84a258e6c6c797fd82d93c12effd6020ef8b5ee860638d511222551f2bd8aaac`, **`0xdc45c`**: the store-bound setter compares normalized current/new statuses before applying changes, contains legacy repeating-template guards, and conditionally makes recursive calls setting related entities to open. Several property/helper identities remain opaque under Swift decompilation. This supports investigating idempotence and related-entity consistency, **not** claiming an exact reconstruction of all cascade rules or UI animation timing.
- `ev_31a64c34587a7bac5b63ddf731200d36a8dbf92307930af865f804d35cfd2856` identifies the searched status/stop-date/logic entry points.

Daybook's fixes are original high-level implementations with independent tests. No proprietary pseudocode, binaries, assets, cloud credentials or personal task data are shipped.

## Still worth improving

- Notification scheduling currently needs real OS-delivery testing, including rapid updates, deduplication/serialization and disable/re-enable behavior.
- Large collections still use some linear relationship lookups and synchronous atomic snapshots. Benchmark and introduce indexes/background persistence before promising 100k-item interactivity.
- Broaden UI tests beyond the checkbox once cross-app permission delivery is repaired.
- The feature-parity matrix remains authoritative: cloud, platform extensions and a full vendor-equivalent rich editor are not implemented.
