# 02 — Shared modules

Status: outline

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

**Resume point.** Reconcile the pilot’s two files against the shared inventory and select the first remaining module batch.
