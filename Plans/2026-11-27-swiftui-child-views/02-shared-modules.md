# 02 — Shared modules

**Status** · executing

Depends on [01 — Installer pilot](01-installer-pilot.md). See the [overview](README.md) for requirements and the [audit](audit.md) for file and symbol locations.

## Outcome and scope

Apply R-01 to the remaining `Shared/` rows, including the rest of InstallerKitUI, previews, test fixtures and support code. R-02 preserves who owns state, effects and public entry points. R-03 requires a disposition and verification evidence for each reviewed surface. X-01 excludes product and public API changes. X-02 excludes permanent lint. The pilot owns `AppUpdatesView.swift` and `UpdateBuildSummary.swift`.

## Boundaries to review

| Area | Extraction and verification |
| --- | --- |
| InstallerKitUI and Broadway | Start with `UpdateBuildRow.version` at five lines. Check the existing browser and build-detail snapshots. Inspect the inline stack in BroadwayCatalog’s `ContentView` and the hosted BroadwayUI fixtures. BroadwayCatalog’s empty test suite provides no rendering evidence. |
| Inspector and PeriscopeTools | `EntityTableView.cellRow` returns a 17-line button. Extract the complete row control with its selection callback, column labels, hit shape, padding and plain button style. Keep `selectedRow` and paging on the table. `InspectorSnapshotTests` covers the sidebar and entity list. Exercise tapping the table row to open its detail and loading the next page. Verify PeriscopeViewer’s search, filters and navigation using hosted behavior checks and the production viewer. |
| Flyover and LifecycleKitUI | `FlyoverConnectorCanvas.connector` measures 39 lines. Preserve the vector drawing and deferred loading of screen content. Use the connector geometry and Flyover snapshot suites. Exercise LifecycleContainer’s ready reveal and gate failure in its hosted suite. The warmed destination must retain one identity through reveal. |
| SnapshotKit, SnapshotKitTesting and shared fixtures | Review `SnapshotCase.framed` and the native-bar fixture in `SnapshotImageRenderingTests`. Preserve configuration-specific frames, fixture mounts and capture hooks. Run the affected capture or hosting suites. Check remaining shared paths, including LifecycleKit and Periscope test hosts, against the inventory. |

## Refinement and acceptance

Use the [small named view inventory](small-named-views.md) to identify existing single-parent children in separate files. Verify their current callers and entry points before choosing the owning file.

After the pilot, use its measurements and verification results to choose independently reviewable module batches. For each qualifying button, measure the complete control and keep its action, label, hit testing, accessibility and control modifiers in the named view. Reuse an existing named view when it already owns that button. Recount the enclosing view after extraction. Keep drawing closures, trait mutations and required modifier witnesses at their existing API boundary. Each batch identifies the concrete inputs and callbacks that preserve ownership.

Accept a batch when every confirmed issue has been fixed and its rendering and interaction checks pass. Record the final control type and file for each qualifying button. A label-only extraction leaves the control finding open. For overlapping inventory entries, reference the completed control. Record the ownership reason for any already-compliant site, and the observed host behavior for paths outside automated coverage.

## Execution and verification

| Slice and source | Ownership and verification |
| --- | --- |
| Installer browser and build detail, `Shared/InstallerKitUI` | Reconcile the pilot files first. Five remaining baseline helper bodies belong to `InstallerBrowserPreview.navigation` (5), `UpdateBrowserView.Route.destination` (6), `UpdateBuildRow.version` (5), `UpdateHero.artwork` (14) and `UpdateInstalledBuild.commit` (6). Inspect complete expressions in Changes, History, BuildView and Channels. Preserve typed navigation and DEBUG preview mounts. The existing two-consumer `UpdateCheckButton` stays shared. Use `UpdateBrowserViewTests` and browser, build, history and AppUpdates snapshot suites. Add `UpdateFailureCardSnapshotTests` when touching that card. |
| Tables and inspector browser, `Shared/Inspector` | Give the whole 17-line `EntityTableView.cellRow` button its row data and selection callback. Table owns paging and selected row. Preserve pinned headers and native deletion confirmation. `InspectorSwiftDataPaginationTests` covers page results and `InspectorSnapshotTests` covers the sidebar/entity list. Exercise row → detail → return, a next-page load and any changed cancel/confirm controls in the mounted table. |
| Log viewer, `Shared/Periscope/PeriscopeTools` | Partition tree/hierarchy navigation from trace, detail, search, filters and export. Keep expanded nodes, selection and destinations on their mounted owners. Use the affected `LogHierarchyViewHostingTests`, `SpanTreeViewHostingTests`, `LogTraceViewHostingTests`, `ScopeEventsViewHostingTests` or `SpanHistoryViewHostingTests`, together with `PeriscopeViewerSnapshotTests`. |
| Flyover and lifecycle, `Shared/Flyover`, `Shared/LifecycleKitUI` | Inspect `FlyoverConnectorCanvas.connector` (39), drawing geometry and the surrounding rendered component. Canvas drawing callbacks take a graphics context. Preserve the warmed lifecycle destination's identity through reveal and gate failure. Select `FlyoverConnectorGeometryTests`, `FlyoverCanvasViewTests`, `FlyoverSnapshotTests`, `LifecycleContainerTests` or `LifecycleReadyRevealStateTests` for the touched owner. |
| Shared harnesses and Broadway, remaining `Shared/` | Reconcile roots, fixtures and small single-parent views by module. Keep `SnapshotCase.framed` configuration and capture hooks on their APIs. Use `SnapshotCaseTests`, `SnapshotImageRenderingTests` and `BRootViewTests` for their corresponding components. Exercise a changed BroadwayCatalog screen in its app. The empty catalog suite establishes no rendered result. |

Apply each slice against its recorded parent. Format and remeasure its complete children, then exercise the named behavior and image suites through `./test --record never --only <bundle>/<suite>`. Compare any failure against the parent before publication. Resume with the first unverified slice and reconcile its paths against the original inventories.

### Installer build browser

UpdateBuildRow and UpdateChangeLink each have 22-line bodies in their own files. The 10-line history link and nine-line workflow row live beside their parents. The six-line commit row and five-line notice each have several callers. The browser, history and build destinations use the same typed routes in production and the hosted test. All 13 Installer behavior tests and five snapshot tests passed on iPhone 17 with recording disabled. The final helper recount for this module found zero qualifying opaque child helpers.

### Snapshot preview and capture fixtures

SnapshotCase keeps lazy preview construction, trait application and capture readiness. Its 16-line preview frame shares the file. The grid keeps its per-image geometry capture. The seven-line centered accessibility button owns its action, original label, padding and frame. The native bar fixture now measures 13 lines and stays with the tests that exercise its actual tab, stack and scrolling geometry.

### Flyover, Broadway Catalog and lifecycle

The complete Fit All, Reset All and Render Preview buttons live with their Flyover parents. The 39-line connector owns its file. FlyoverControlBar and FlyoverOverview remain visible to their snapshot harness. Broadway Catalog keeps its eight-line home view beside the app and the scroll fixture keeps its six-line target rows. LifecycleContainer keeps one mounted destination across readiness and gate transitions.
