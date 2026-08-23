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
- test [needs-design]: The engine is well covered but the interactive surfaces are not. **Twelve** test files pin what the module computes (re-counted 2026-08-16; was ten when filed) — the catalog, layout, model, canvas render and zoom plans, connector geometry, preview readiness, the serial content-load coordinator, and the stylesheet — while the UI it drives is verified only by the single `canvasAndList` image case, now **5** references. Untested: the focused inspector, the viewport and appearance menus, and the overview↔focus transition edge cases. **This window widened the gap rather than closing it:** PR #257 (horizontal canvas groups, two-axis full-content capture) and PR #268 (viewport-centered zoom) both landed with unit coverage of the new *plans* — `FlyoverConnectorGeometryTests`, `FlyoverCanvasZoomPlanTests` — and #257 added one reference (`canvasAndList.FlyoverCanvasFullContent_iPad.png`), so the module keeps proving its math while the surfaces it drives stay unpinned. **Flyover shipped nothing at all in the 2026-08-23 window** — twelve test files, five references, and the single `canvasAndList` case are all unchanged — so the gap held rather than widening for once. Acceptable for a DEBUG-only tool, and deliberately not a hosting-smoke-test gap (the repo's convention is that an image bundle owns "does this screen render"), so the shape of the fix is more `SnapshotProviding` cases in [`SnapshotTests/`](SnapshotTests) rather than new unit tests — decide which surfaces are worth pinning before adding them wholesale. (audit 2026-08-09; re-verified 2026-08-23)

# Completed issues
