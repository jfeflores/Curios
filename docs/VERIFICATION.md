> Historical Daybook verification record. Current Curios V1 results and security regressions are in [V1_HARDENING.md](V1_HARDENING.md).

# Verification ledger

## Current results

- **44/44 domain tests passed**, zero assertion failures.
- **17/17 application-store integration checks passed**.
- **Two native checkbox UI scenarios passed**: collapsed task row and expanded task editor. Each completed and reopened a task using independent mouse-down/up sequences.
- SourceKit LSP: **0 diagnostics across 16 source/test files**.
- Native app compiles with the existing stable macOS 15.4 SDK, targets macOS 14+, and passes ad-hoc signature verification.
- Optional calendar/notification permission grants and deliveries have **not** been exercised.

Run:

```sh
./scripts/test.sh
./scripts/ui-test.sh
./scripts/build.sh
```

## Checkbox regressions: more than model tests

The opt-in UI self-test launches a separate `local.daybook.review` bundle with a newly created `ui-test-*` profile for each scenario. It never reads normal Daybook or Things data and does not register the global hotkey. It discovers the actual native `NSButton` by stable accessibility identifier **within its own NSView hierarchy**, then sends mouse-down/up events through its own `NSWindow` at that button's real converted frame. It does not call `AppStore.complete` directly.

Scenarios:

1. **Today list**: click the native checkbox on a collapsed task row.
2. **Expanded editor**: open the first task's editor, then click its native checkbox. This specifically prevents regressing to the original decorative, non-interactive square.

For each scenario, the test reads saved JSON and live control state after each click and verifies:

- Initial task is open; its checkbox is enabled/off.
- First click persists `completed`.
- The rendered checkbox becomes on/checked, rather than disappearing without feedback.
- The task is present in Logbook immediately.
- No extra task is created by a conflicting gesture.
- Second click reopens the task and returns the native control to off.

Successful local reports and rendered readbacks:

```text
.analysis/ui-test-today-PxMHtN/report.json
.analysis/ui-test-today-PxMHtN/checkbox-checked.png
.analysis/ui-test-today-PxMHtN/checkbox-reopened.png
.analysis/ui-test-editor-xdUxRF/report.json
.analysis/ui-test-editor-xdUxRF/checkbox-checked.png
.analysis/ui-test-editor-xdUxRF/checkbox-reopened.png
```

Both reports include `passed: true`, `visibleCheckmark: true`, `persistedCompleted: true`, `presentInLogbook: true`, and `secondClickReopened: true`. These are actual readbacks, not assumed effects of sending inputs. Converted frames were `{{311.5, 519}, {24, 24}}` for the collapsed control and `{{332.5, 558.5}, {24, 24}}` for the editor control.

This is genuine **in-process Cocoa hit-testing/control tracking** verification, not a hardware mouse test or a full external accessibility audit. Orca cross-app automation remains blocked: `get-app-state` reports Accessibility denied even when its permission-status helper reports granted. We did not repeatedly retry or alter TCC settings. The app's own rendering and synthetic-profile tests do not require cross-app access.

## Coverage

Domain: day validation and daylight-saving boundaries; scheduling vs deadlines; future/overdue visibility; project/Someday inheritance; inherited/nested tags; search; fixed/after-completion and month-end recurrence; selected/ordinal weekdays; end dates; lead times; idempotent generation; project/heading copying; precise completion groups; container reopening; trash/restore; duplication; date parsing; persistence/backup/corrupt-input safety; non-destructive mixed tag edits; independent batch reminders; explicit deadlines; tag shortcut validity and batch intent; stale editor field merges preserving completion, trash, ordering and other-window changes; identity mismatch rejection.

Application: first-run persistence; creation; visible completion acknowledgement; undo/redo; scheduling; trash/restore; own URL parsing; tags; repeat-template generation/stopping; deterministic mixed/parent-child batch completion; tag patches; reminder preservation; custom tag shortcut dispatch model; optional same-day finished-item visibility after restart; stale editor completion/trash safety and no resurrection after removal; reload; invalid-transaction rollback; read-only corrupt data protection.

## Remaining verification gaps

- External input delivery, modifier-click cancellation, custom shortcut event routing, menus, other editor controls, date/tag popovers, drag/drop and multi-window interaction.
- VoiceOver and full keyboard-access settings.
- Real notification permission/delivery behavior and rapid-edit notification ordering.
- Personal calendar permissions, calendar changes, timezone travel and long-running event refresh.
- File-panel import/export interactions (validation/merge/store paths are separately covered).
- Large-dataset performance and extended recurrence fuzz/property tests.

The beta CLT SwiftPM manifest failure is an environment issue, not a passing SwiftPM test run. `scripts/test.sh` directly compiles the same domain test classes with a small assertion runner and additionally executes real application-store code. A matching Xcode toolchain can run those classes under XCTest with `swift test`.
