# Remove RTL coverage and focus calendar snapshots

## Planning checkpoint

- Updated: 2026-11-17. The user requested removal of RTL snapshots/defaults and month-sized calendar coverage with a few full-height checks.
- Operation: Implement both changes, validate retained and reframed coverage, and publish above PR #520.
- Branch/base: `test/snapshot-reviewability`, based on `b0dfa58cb`.
- Stage: Complete; [PR #521](https://github.com/kyleve/Stuff/pull/521) is ready for review above #520 in [stack #522](https://github.com/kyleve/Stuff/stack/522).
- Completed: Removed six RTL references in `fdb86b6bd`; focused calendar subjects in `2359e93e0`. The full-year reference preserves the original image byte for byte. Final assertions pass all 162 captures and 25 calendar-related unit tests; the earlier run passes 26 configuration tests. Independent source, visual, and raw-evidence review found no actionable issues. Published image comments and links are verified.
- Pending: Remote CI results and PR review; no implementation work remains in these plans.
- Next action: Follow PR #521's checks and review. STU-121 remains In Review for the open PR and broader performance work.

## Requirements and scope

US-01: Review useful calendar differences without scanning many repeated months.
R-01: Remove every RTL image case/reference and keep RTL out of default capture matrices.
R-02: Most calendar content cases render one representative production month, with full-height coverage retained for year composition and screen integration.
R-03: Preserve state coverage for recording gaps, evidence/flights, region focus, planning, current-day styling, themes, accessibility, and year overview.
R-04: Record only intentional reframing. Enumerate removed/retained identities, inspect new images, then run assertions with recording disabled.
X-01: Do not change production RTL behavior, remove explicit layout-direction APIs, or weaken pixel comparison/settling policy.
X-02: Do not crop content or add snapshot-specific production layout branches. Reuse production month rendering and report data.

## Execution order

1. [Remove RTL cases](01-remove-rtl.md), independently verified and committed.
2. [Focus calendar subjects](02-calendar-months.md), refined after choosing coverage boundaries.

[STU-121](https://linear.app/kve/issue/STU-121) tracks this continuation. Existing performance-plan records remain unchanged.

## Questions and evidence

Q-01 (closed, R-01): Six explicit RTL PNGs belong to MainTabs (three), Settings (one), and onboarding theme selection (two). Representative presets omit RTL already; Flyover defaults to phone light/dark. Keep the explicit RTL API and its unit coverage for future opt-in use. This implements the user's image-coverage request without altering app direction handling.

Q-02 (closed, R-02/R-03): Plan 02 records the selected month for every detail state, two full CalendarContentView captures, two full YearView integrations, preserved overview coverage, and focused picker traits. It also preserves ordinary full-screen scenario previews/Flyover. Existing detail PNGs reach 17,510px; YearView's AX5 image reaches 18,102px. Source/fixture review and visual inspection on 2026-11-17 support the selection; plan 02 records the comparison evidence.

## Plan review

2026-11-17, `b0dfa58cb`: plan 01 is mechanical and preserves all remaining configurations. No new architecture or Swift pseudocode is needed. Plan 02 remains an outline until the selected months, production rendering boundary, and retained integration matrix are explicit. The user has authorized both steps; routine coverage choices can proceed from the inspected risks.
