# Remove RTL coverage and focus calendar snapshots

## Planning checkpoint

- Updated: 2026-11-17. The user requested removal of RTL snapshots/defaults and month-sized calendar coverage with a few full-height checks.
- Operation: Implement both changes, validate retained and reframed coverage, and publish above PR #520.
- Branch/base: `test/snapshot-reviewability`, based on `b0dfa58cb`.
- Stage: RTL inventory complete; calendar coverage design.
- Completed: Found six RTL references and their three owning providers. Shared presets and Flyover export defaults already use left-to-right layout.
- Pending: Remove RTL variants, map calendar states to representative months, record/review new subjects, verify retained integration coverage, and publish.
- Next action: Execute plan 01; refine plan 02 from the calendar fixtures and existing reference dimensions.

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

Q-02 (open, R-02/R-03): Which month best represents each detail state, and which whole-screen/year captures remain? Existing detail PNGs reach 17,510px; YearView's AX5 image reaches 18,102px. Overview has a distinct twelve-month composition and must retain its own coverage.

## Plan review

2026-11-17, `b0dfa58cb`: plan 01 is mechanical and preserves all remaining configurations. No new architecture or Swift pseudocode is needed. Plan 02 remains an outline until the selected months, production rendering boundary, and retained integration matrix are explicit. The user has authorized both steps; routine coverage choices can proceed from the inspected risks.
