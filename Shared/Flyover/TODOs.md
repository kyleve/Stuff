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
- test [needs-design]: The engine is well covered but the interactive surfaces are not. Ten test files pin what the module computes — the catalog, layout, model, canvas render and zoom plans, the serial content-load coordinator, and the stylesheet — while the UI it drives is verified only by the single `canvasAndList` image case (4 references). Untested: the focused inspector, the viewport and appearance menus, and the overview↔focus transition edge cases. Acceptable for a DEBUG-only tool, and deliberately not a hosting-smoke-test gap (the repo's convention is that an image bundle owns "does this screen render"), so the shape of the fix is more `SnapshotProviding` cases in [`SnapshotTests/`](SnapshotTests) rather than new unit tests — decide which surfaces are worth pinning before adding them wholesale. (audit 2026-08-09)

# Completed issues
