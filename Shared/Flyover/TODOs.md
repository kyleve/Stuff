# Flyover todos

The backlog for the Flyover module — the app-agnostic developer browser that
renders a catalog of screens as a zoomable canvas or list.

The item format and the placement rule live in the root
[`TODOs.md`](../../TODOs.md); raw notes go in [`INBOX.md`](../../INBOX.md), not
here.

# Open issues

## P1s (Should do)
- test [needs-design]: The module shipped 50 sources against 10 namesake test files, so most of it has no 1:1 coverage. What is covered is the model layer — catalog validation (`FlyoverCatalogTests`), the six-screen live cap (`FlyoverCanvasRenderPlan.swift:5-7`), the serial load coordinator, zoom/appearance plans — and four canvas/list reference images (`SnapshotTests/FlyoverSnapshotTests.swift`). What isn't: `FlyoverCanvasView` (viewport, preview, and focus interaction), `FlyoverRootView` (including the invalid-catalog path), `FlyoverConnectorCanvas`, `FlyoverFocusedView`, the control-bar and menu views, and the `FlyoverGroup*` types. Add tests for the behavioral types first and leave rendering to the image suite; the two together are what the root convention asks for. Flyover is a DEBUG developer tool, so this is a coverage debt to pay down rather than a shipping risk — but it is the largest untested surface in the repo. (audit 2026-08-02)

## P2s (Nice to have)
- feat [quick-win]: An invalid catalog reports only how many problems it has, not what they are. `FlyoverRootView.swift:14-19` renders a `ContentUnavailableView` whose description is `"\(catalog.validationIssues.count) structural issue(s) must be fixed."`, so a developer who mis-wires a route learns that one thing is wrong and nothing about which. The issues are already modelled and populated (`FlyoverCatalogValidationIssue.swift`) — list them in the unavailable view, or put them behind a drill-in. This is the whole audience: an invalid catalog only ever reaches a developer. (audit 2026-08-02)
	- docs [quick-win]: `README.md:99-100` says an invalid catalog "renders a diagnostic instead of a partial map", which reads as though the issues are shown. Once the view lists them the sentence becomes true; until then it oversells. (audit 2026-08-02)
- test [quick-win]: `FlyoverCanvas` is the only image case on a 1.5s `.settledAtLeast` floor outside Where (`SnapshotTests/FlyoverSnapshotTests.swift:20`), added by #166 to stabilize it. A deterministic completion signal on the content-load coordinator would let the floor come off; see the settle-floor item in [`Shared/SnapshotKitTesting/TODOs.md`](../SnapshotKitTesting/TODOs.md), which this is now part of the cost of. (audit 2026-08-02)

# Completed issues
