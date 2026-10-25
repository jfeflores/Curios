# Feature parity and remaining work

> Historical Daybook prototype ledger. Curios V1 security, capture, file-handling and release-identity updates are documented in [V1_HARDENING.md](V1_HARDENING.md); this matrix is not a current security certification.

**Not a claim of all-feature or byte-for-byte parity.** Things is a mature, multi-platform product with a proprietary service. This first build recreates substantial local macOS functionality and the core list/editor visual structure. Evidence scope is in `REVERSE_ENGINEERING.md`; no user database was inspected.

Legend: **Implemented** = working code, covered by domain/application tests where indicated; **Partial** = a bounded independent subset; **Unverified OS/UI** = real integration code, but permission/UI delivery wasn't exercised; **Not implemented** = no fake stand-in, disabled placeholder, or vendor service access.

| Feature | Status | Boundary / verification |
|---|---|---|
| Inbox capture | Implemented | Selected-list drafts, quick entry and multiline capture; app tests |
| Today and overdue carry-over | Implemented | Readiness uses calendar days; overdue start/deadline cases tested |
| This Evening | Implemented | Orthogonal bucket, consistent with Ghidra's native default/evening enum; visual render |
| Upcoming | Implemented / partial parity | Groups the next relevant future marker and optional calendar events; does not claim identical multi-marker layout or infinite virtual recurrence previews |
| Anytime / Someday | Implemented | Project scheduling and Someday inheritance tested |
| Tomorrow / Deadlines | Implemented | Reachable from Quick Find and Navigate menu |
| All Projects / Logged Projects | Implemented | Dedicated navigation lists |
| Repeating list | Implemented | Templates with next date, pause/resume/stop and next-copy actions |
| Logbook / cancellation | Implemented | Persisted immediately with brief visible checkmark feedback; optional finished-in-Today display until day end. Native delayed/manual log timing is not reproduced. Checkbox click/reopen is native-UI-regression tested |
| Trash / restore / empty | Implemented | Recursive project/repeater relationships and old-trash preservation tested; undo available in current session |
| Task title and notes | Implemented | Inline editor with save/cancel; field-aware commits preserve live completion, trash and other-window edits. Expanded completion checkbox is native-mouse regression tested |
| Markdown | Partial | Inline formatting and heading-oriented preview; no complete vendor rich editor, writing tools, text find/replace, task-list or fenced-code equivalence |
| Checklists | Implemented | Add/edit/remove/toggle entries; copies get fresh entry IDs; templates aren't completable |
| Project notes / tasks / progress | Implemented | Progress from non-trashed children, completion/reopen cascade tested |
| Project headings | Implemented / partial | Create, rename, group, reorder via item positions, archive or trash; no complete heading-to-project/project-to-task conversion workflow |
| Areas | Implemented | Create, rename, tags and removal without deleting contained work |
| Tags / nested tags | Implemented | Create, rename, parent, remove; invalid cycles rejected |
| Inherited tags | Implemented | Union project/area/ancestor tags; explicit tags remain separate; tested |
| Tag AND filtering | Implemented | Command-click multiple tags; exact native interaction isn't GUI-tested |
| Custom tag shortcut bindings | Implemented / external keyboard unverified | Unique case-insensitive letter/number bindings editable in Tags; Control-key toggles tags, Control-Option-key toggles filters; validation and batch intent tested |
| Independent start date / deadline | Implemented | Separation and changing start without changing deadline tested |
| Natural-language dates | Partial | Bounded English today/tomorrow/evening, weekdays, next week/month, `in N units`, ISO dates and clock times; not the vendor's complete localized parser |
| Timed reminder scheduling | Unverified OS/UI | Opt-in UserNotifications; only open, non-template tasks; no permission granted during verification |
| Calendar events | Unverified OS/UI | Read-only EventKit, selected calendars, Today/Upcoming, 31-day window; no personal calendar data accessed |
| Daily/weekly/monthly/yearly repeats | Implemented | Anchored regular schedule and after-completion tested; month-end drift avoided |
| Weekday / ordinal repeat rules | Implemented | Weekly selected weekdays and nth/last weekday of month tested |
| Multiple month days | Partial | Supported in engine/JSON; UI exposes anchored or ordinal monthly days, not the complete advanced day-combination editor |
| Yearly multiple-month schedules | Not implemented | Single anchor month only |
| Repeat end / deadline lead time | Implemented | End boundary and early start with later deadline tested |
| Template/copy separation | Implemented | Idempotent occurrence keys, independent checklists, project/heading remapping tested |
| Repeating projects | Implemented | Whole template tree copied with new IDs; restore copies and children tested |
| Repeat generation while app closed | Partial | Catch-up on launch / minute refresh, not a separate background agent or cloud push engine |
| Pause / resume / stop / create next copy | Implemented | Context menu; app stop unlinks copies safely |
| Quick Find / Type Travel | Implemented / UI unverified | Title-first navigation and special lists, tags, areas and projects |
| Full search | Implemented | Notes/checklists/Logbook scope and multi-term matching tested |
| Navigation / create / complete keyboard commands | Implemented / UI unverified | Core shortcut set in README; no claim of every vendor shortcut |
| Quick Entry window | Implemented / UI unverified | Own window sharing store; registered global Ctrl-Shift-Space instead of conflicting system Ctrl-Space |
| Quick Entry with source autofill | Not implemented | No cross-app content harvesting |
| Multi-select / batch operations | Implemented / popup UI unverified | Deterministic completion intent; patch-based mixed tags; explicit date actions preserve individual reminder times; dismissing without an action is a no-op. Regression tested at domain/store level |
| Drag-and-drop | Partial | Individual rows reorder; sidebar project/area/list targets move items. No complete multi-item drag previews, cross-app rich payloads or Magic Plus |
| Clipboard capture | Partial | One task per plain-text line; no native rich task payload compatibility |
| Duplication | Implemented | Project children and heading IDs remapped; tested |
| Undo / redo | Implemented | Whole-database atomic transactions; app-tested; current process only |
| Multiple windows / slim mode | Implemented / UI unverified | Shared main-actor store, per-window navigation; independent sidebar state |
| Light / dark / system appearance | Implemented | Own-window render and source inspection; not pixel-equivalence against private UI |
| Core visual language | Implemented approximation | Sidebar/list hierarchy, generous whitespace, colored icons, restrained rows, inline paper editor, progress rings and evening section; original code/SF Symbols/content |
| Atomic persistence / backup / recovery | Implemented | Failed/corrupt import safety, round-trip and backup tests |
| JSON import/export | Implemented / file-panel UI unverified | Versioned Daybook-only format, ID-based merge, no vendor DB import |
| Own URL scheme | Implemented | `daybook://add` and `show`; app-level handling tested; Launch Services external delivery not exercised |
| AppleScript dictionary / native Things URL compatibility | Not implemented | Vendor declaration inspected, not copied or impersonated |
| Shortcuts / App Intents / Siri | Not implemented | Separate extension milestone |
| Widgets / menu-bar extension / share extension | Not implemented | Separate target/entitlements work |
| Reminders import / contacts / Handoff | Not implemented | No private OS data accessed |
| Printing / Touch Bar / full accessibility audit | Not implemented / partial | Native controls expose labels; full audit and parity remain open |
| Things Cloud / own sync backend | Not implemented | No use of vendor accounts, credentials, endpoints or protocols |
| Mail capture / push fastlane | Not implemented | Requires independent service/infrastructure |
| iOS / iPad / watch clients | Not implemented | This repository targets macOS only |

## Highest-priority next milestones

1. The checkbox's native mouse/control/disk regression now passes. Resolve external Orca Accessibility delivery to expand GUI coverage to editing, pickers, search, custom shortcuts, drag/drop, multi-window behavior and VoiceOver.
2. Exercise optional calendar/notification permissions in a deliberately selected test account and verify actual deliveries and teardown.
3. Expand recurrence corner cases, catch-up policy, advanced monthly/yearly controls and automated long-horizon/property tests.
4. Complete rich notes, advanced list conversions, clipboard/drag payloads and import/export UI tests; externally verify the newly implemented tag bindings.
5. Design an independent sync service and platform extensions if cross-device parity is required. Vendor cloud access is not a shortcut to this milestone.
