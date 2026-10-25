# Things investigation and independent reconstruction

> Historical prototype investigation ledger. Current Curios V1 verification and hardening are in [V1_HARDENING.md](V1_HARDENING.md). Raw investigation inputs/evidence remain local and are excluded from publication.

## Scope and boundaries

- User-selected target: `/Applications/Things3.app`, **3.22.14 (32214000)**, `com.culturedcode.ThingsMac`.
- Product: **Daybook**, native macOS SwiftUI/AppKit, original code/branding/icon/sample content, separate local-first data.
- No Things user-data container, personal database, account or private UI was accessed. No vendor cloud service or assets are included.
- Complete parity remains a goal, not an established result. See `FEATURE_PARITY.md`.

## Completed work

- [x] Resolve installed artifact and inspect build environment.
- [x] Inventory shipped resource/scripting declarations and public behavior documentation.
- [x] Preserve original/derived binary digests and use REA/Ghidra on the shipped ARM64 model framework.
- [x] Inspect start/evening, tag-inheritance, repeat-configuration and status-setting entry points; document native observations separately from inference.
- [x] Export seven initial and four completion-review evidence records, then close native sessions.
- [x] Recreate core sidebar/list/inline-editor visual structure with original resources.
- [x] Implement a substantial local macOS workflow set, with explicit partial/missing features in the parity matrix.
- [x] Build/ad-hoc sign the app with the existing stable SDK and validate source with SourceKit LSP.
- [x] Pass 44 domain tests and 17 application integration checks.
- [x] Verify collapsed-row and expanded-editor checkbox mouse-down/up, visible checkmarks, persisted completion, Logbook membership and reopening in two isolated native UI scenarios.
- [x] Replace the expanded editor's decorative square with a real control; merge edited fields without undoing live status/trash changes or resurrecting deleted records.
- [x] Review/fix destructive batch tag/date behavior, deterministic batch completion, container reopening, completion grouping and tag-filter visibility.
- [x] Add unique custom tag shortcuts and optional visible finished items in Today.

## Open work

- [ ] Restore external Orca Accessibility delivery, then verify broader real GUI interactions and VoiceOver.
- [ ] Exercise opt-in calendar and notification integrations with intentionally granted permissions/test data.
- [ ] Benchmark large datasets; broaden recurrence/property tests and OS integration ordering checks.
- [ ] Continue feature parity for advanced rich editing, import/drag payloads, platform extensions, independent cloud sync and non-macOS clients.

## Evidence and verification

- `REVERSE_ENGINEERING.md`: artifact hashes, initial evidence and public references.
- `REVIEW.md`: new completion evidence, reviewed defects/fixes and remaining risks.
- `VERIFICATION.md`: exact test scope, results and gaps.
- `.analysis/`: ignored local slices, full evidence bundles/snapshot, logs, synthetic data and own-app screenshots. Not part of the distributable.

## Adaptations and limitations

- Subagent panes require tmux and were unavailable; no nonexistent parallel-agent results are claimed.
- Ghidra refuses universal Mach-O architecture selection through this REA provider; Apple `lipo` derived ARM64 slices without modifying the originals.
- The large main executable exceeded Ghidra's 330-second deadline. Its partial work is not treated as behavior evidence. The smaller shipped model framework completed analysis.
- The installed beta CLT has mismatched package interfaces / an incomplete default-SDK macro plugin. Project-local scripts use the already-installed stable SDK, without system changes or software installation.
- Orca's permission-status and get-app-state responses disagree. Own-window rendering and the in-process test do not imply cross-app automation succeeded.
