# 02 — Shared modules

Status: outline

Depends on [01 — Installer pilot](01-installer-pilot.md). See the [overview](README.md) for requirements and the [audit](audit.md) for file and symbol locations.

## Outcome and scope

Apply R-01 to the remaining `Shared/` rows, including the rest of InstallerKitUI, previews, test fixtures and support code. R-02 preserves who owns state, effects and public entry points. R-03 requires a disposition and verification evidence for each reviewed surface. X-01 excludes product and public API changes. X-02 excludes permanent lint. The pilot owns `AppUpdatesView.swift` and `UpdateBuildSummary.swift`.

## Boundaries to review

| Area | Extraction and verification |
| --- | --- |
| InstallerKitUI and Broadway | Start with `UpdateBuildRow.version` at five lines. Check the existing browser and build-detail snapshots. Inspect the inline stack in BroadwayCatalog’s `ContentView` and the hosted BroadwayUI fixtures. BroadwayCatalog’s empty test suite provides no rendering evidence. |
| Inspector and PeriscopeTools | Group Inspector’s header, row and footer around `EntityTableView`. Keep selection and paging on their current owner. `InspectorSnapshotTests` covers the sidebar and entity list. Exercise table selection and paging separately. Verify PeriscopeViewer’s search, filters and navigation using hosted behavior checks and the production viewer. |
| Flyover and LifecycleKitUI | `FlyoverConnectorCanvas.connector` measures 39 lines. Preserve the vector drawing and deferred loading of screen content. Use the connector geometry and Flyover snapshot suites. Exercise LifecycleContainer’s ready reveal and gate failure in its hosted suite. The warmed destination must retain one identity through reveal. |
| SnapshotKit, SnapshotKitTesting and shared fixtures | Review `SnapshotCase.framed` and the native-bar fixture in `SnapshotImageRenderingTests`. Preserve configuration-specific frames, fixture mounts and capture hooks. Run the affected capture or hosting suites. Check remaining shared paths, including LifecycleKit and Periscope test hosts, against the inventory. |

## Refinement and acceptance

Use the [small named view inventory](small-named-views.md) to identify existing single-parent children in separate files. Verify their current callers and entry points before choosing the owning file.

After the pilot, use its measured before-and-after bodies and verification results to choose independently reviewable module batches. Extract the innermost child first, then recount its parent before choosing a file. Keep drawing closures, trait mutations and required modifier witnesses at their existing API boundary. The pilot’s ownership sketch applies here. Each batch adds its concrete view inputs and callbacks at refinement.

Accept a batch when its reviewed rows have final placements or a source-backed reason to retain them, and its affected rendering and interaction checks pass. Record any uncovered paths and the observed host behavior.

**Resume point.** Reconcile the pilot’s two files against the shared inventory and select the first remaining module batch.
