# Evidence-backed investigation of Things 3.22.14

## Artifact identity

Read only the installed application bundle. No Things user-data container, database, account, or running task list was opened.

| Input | SHA-256 |
|---|---|
| Original universal `Contents/MacOS/Things3` | `93e007596ab013748fb5d107645f5c0de48fc129d3c4590f0313034785bda4ac` |
| Derived ARM64 main executable | `1e6898a7fc073433da11a7e8addab2eef90fa748d1e2cac2df578551ca7b6187` |
| Original universal `ThingsModel.framework/ThingsModel` | `1dfde7f9474d07442ec002faa78183f6cd1b429fc6ce7870af31f36e5a2511a0` |
| Derived ARM64 model framework | `3555e9e128c5e49792403a09104ac492008cde18c3b39bbd7cd4b2a88403d6e6` |

Slices were derived with Apple `lipo -thin arm64`. REA 6.7.0 and Ghidra 12.1.4 imported the model framework with `AARCH64` automatic loader and default analysis. REA refused the universal input (architecture selection unsupported); the large main executable exceeded the 330-second startup deadline. Its partial analysis is **not** evidence of behavior. Switching to the smaller, shipped model framework completed successfully without disabling analyzers or changing global configuration.

## Native findings and limitations

| Question | Evidence | Observation / inference |
|---|---|---|
| How is evening represented? | `ev_5a902ab08ccc07b84f379ad55c9b2b4335ed51785e8f70c9d620b770996e5a4f`, address `0xe0388` | The start-bucket description getter branches on 0 and 1 and returns Swift small strings decoding to `default` and `evening`. This supports an orthogonal day/evening bucket, not a second deadline field. |
| Are start day and reminder time distinct? | `ev_881e8b4a68fc7e060d176d2f1e3510ff6fef9201db89ef3918ebccc025260d91`, `0xfb344` | The Objective-C scheduling entry accepts start/startDate/startBucket/reminderTime and converts day and time through separate `FADayValue` / `FATimeValue` calls. Swift calling conventions confuse some recovered parameter types; the full downstream state-transition algorithm is not established by this wrapper. |
| Are inherited tags materialized independently? | `ev_c15a753855f8300833263e7dc554b59489be9401624af05f9360364f941f44e5`, `0xf237c` | The inherited-tag getter returns a Swift Set and traverses containing-project and area entities. The inference of union/inheritance is corroborated by the official tag documentation; opaque helper calls prevent a claim of full native semantic equivalence. |
| How is repetition modeled? | `ev_14c7f56eda785b13f620ae4132fd27c46f52304e10a24a6babe0646ae6a4e928`; `ev_f9e7fb44c3e8c3e20b3a734b3a6df4957ae789bca85cfa559f4ae6b524e73bce`, `0x6f830` | Named procedures expose repeat type, interval unit/span/anchor, serialization and configuration equality. The setter helper mutates a wrapped `TaskRepeater.RepeaterConfiguration`. Exact occurrence generation and sync merge rules were **not** reconstructed; Daybook implements the publicly documented behavior independently. |

The wrapper at `0x6f824` (`ev_8fcfea0819029992e694a9f6e14728e65dbf6582cc777a444d70223fc34ee051`) was only a terminal call; its helper was followed rather than treating that wrapper as a complete algorithm. Search evidence for inherited tags is `ev_825e9562e7ac1e0b0d753e17fb5ec45f708895ee0c8239fc38a5bf04edd00b84`.

Full REA evidence (seven records) and the closed-session snapshot are retained locally in ignored `.analysis/ThingsModel-evidence.json` and `.analysis/ThingsModel-snapshot.json`. Decompiled text is provider reconstruction, not original source. Native session closed successfully after export.

## Shipped resource evidence (shell inspection, not REA)

`Things.sdef` declares task/project/area/tag models, creation/modification/activation/due/completion/cancellation dates, statuses, tag parent relationships and shortcuts, quick entry, move/schedule, duplication, logbook and trash operations. English localization and nib names corroborate checklists, heading operations, reminder/deadline pickers, recurrence, calendar/reminder imports, URL schemes, and sync settings. Declarations and strings establish a feature surface, not runtime behavior or algorithm correctness. No vendor resources are included in the product.

## Public behavior specification and visual reference

- [Feature overview](https://culturedcode.com/things/features/) — whitespace-led native layout, colored list glyphs, understated list rows, inline detail cards, project progress circles, optional evening section, multiple windows and slim mode.
- [Scheduling](https://culturedcode.com/things/support/articles/2803579/) — start dates determine availability; deadlines independently specify finish dates; overdue scheduled tasks remain relevant.
- [Tags](https://culturedcode.com/things/support/articles/2803581/) — inheritance from project/area, nested tags, AND filtering for multiple selected tags.
- [Repeating tasks](https://culturedcode.com/things/support/articles/2803564/) and [patterns](https://culturedcode.com/things/support/articles/3743733/) — template/copy separation, regular vs after-completion, daily/weekly/monthly/yearly intervals, selected days, pause/resume/stop, end date and deadline lead time.
- [Quick Find](https://culturedcode.com/things/support/articles/2803584/) — title-first navigation; explicit deeper search includes notes/checklists/logged items; special Tomorrow/Deadlines/Repeating/All Projects/Logged Projects lists.
- [Keyboard shortcuts](https://culturedcode.com/things/support/articles/2785159/) — creation, completion/cancellation, navigation, scheduling, tag filtering and moving.

The visual reference is the publisher's public macOS screenshot linked from the feature page. Layout resemblance is an independent recreation, not a pixel-equivalence assertion. No private Things UI or task content was captured. Brand marks, illustrations, proprietary animations, icons, help copy, and cloud protocols are not copied.

## Completion/status follow-up

A second targeted REA/Ghidra pass recovered the status-description getter and public/store-bound status setters. Observed native values are 0=open, 2=canceled and 3=completed; the setter includes a same-status early exit and conditional related-entity reopening. Full cascade/property mappings and UI animation timing remain only partially understood. Exact addresses, four new Evidence IDs, code-review implications and tests are recorded in [REVIEW.md](REVIEW.md). The additional bundle is retained separately as `.analysis/ThingsModel-completion-evidence.json`, and that session was closed after export.
