# Flyover todos

The backlog for Flyover, the app-agnostic developer screen browser.

The item format and the placement rule live in the root
[`TODOs.md`](../../TODOs.md); raw notes go in [`INBOX.md`](../../INBOX.md), not
here.

Flyover's known cross-module issue — its unactivated sibling demo world still
reaching the active scope's durable diagnostic store through the process-global
`WhereLog` facade — is filed in [`Where/TODOs.md`](../../Where/TODOs.md),
because the fix is Where's to make.

# Open issues

## P2s (Nice to have)
- test [needs-design]: The engine is well covered but the interactive surfaces are not. **Fourteen** test files pin what the module computes (re-counted 2026-08-30 — the item said twelve, which undercounted `FlyoverContentLoadCoordinatorTests` and `FlyoverConnectorGeometryTests`; it was ten when filed) — the catalog, layout, model, canvas render and zoom plans, connector geometry, preview readiness, the serial content-load coordinator, and the stylesheet — while the UI it drives is verified only by the single `canvasAndList` image case, now **5** references. Untested: the focused inspector, the viewport and appearance menus, and the overview↔focus transition edge cases. **This window widened the gap rather than closing it:** PR #257 (horizontal canvas groups, two-axis full-content capture) and PR #268 (viewport-centered zoom) both landed with unit coverage of the new *plans* — `FlyoverConnectorGeometryTests`, `FlyoverCanvasZoomPlanTests` — and #257 added one reference (`canvasAndList.FlyoverCanvasFullContent_iPad.png`), so the module keeps proving its math while the surfaces it drives stay unpinned. Flyover shipped nothing in the 2026-08-30 or 2026-09-06 windows, so the gap is unchanged rather than widened again (still 14 test files, 5 references). PR #333 (`ff89e122`, merged 2026-10-07) replaces the graph-sized connector bitmap with vector paths and updates the Where overview reference; it does not add focus/menu/transition cases. The October 12 inventory remains 14 test/support files and 5 Flyover references. Acceptable for a DEBUG-only tool, and deliberately not a hosting-smoke-test gap (the repo's convention is that an image bundle owns "does this screen render"), so the shape of the fix is more `SnapshotProviding` cases in [`SnapshotTests/`](SnapshotTests) rather than new unit tests — decide which surfaces are worth pinning before adding them wholesale. (audit 2026-08-09; re-verified 2026-09-06)

# Completed issues

- fix [quick-win]: Show capture-load failures with recovery. `Web/src/scripts/previews.ts:18-28` creates images without an error state or retry action. A failed request, or an old open tab after a deployment removes its image path, leaves a broken capture while the surrounding metadata looks valid. Add an accessible failure state with retry/reload guidance and browser tests for 404, interrupted requests, and successful recovery. (agent review 2026-10-26) **Closed: failed previews provide inspector guidance; the inspector offers retry and URL-preserving reload. Browser tests cover HTTP errors, interrupted requests, failed retries, successful recovery, and error-state accessibility.** (closed 2026-10-26)
- test [needs-design]: Extend browser coverage beyond viewport resizing. `Web/playwright.config.ts:15-19` covers Chromium/WebKit at desktop, portrait, and landscape sizes, but no test drives the two-touch handler in `Web/src/scripts/canvas-controller.ts:145-181`. Add real touch-gesture coverage, automated accessibility scanning, and deterministic request/decoded-image budgets using a representative catalog. Keep timing measurements advisory until a stable runner baseline exists. The current 126 browser regressions passed during review. (agent review 2026-10-26) **Closed: Chromium portrait drives real two-touch input. Chromium and WebKit run axe scans and deterministic thumbnail-request/decoded-pixel guards at desktop, portrait, and landscape sizes. Timing measurements remain advisory.** (closed 2026-10-26)
