# 01 — Share immutable snapshot paths

- Status: executing
- Depends on: None
- Shared requirements: [Overview](README.md), R-01, R-02, R-04, R-05; exclusions X-01 and X-02.

## Design

`PreviewSupport` creates one DEBUG-only `RegionOutlinePathCache`. Snapshot helpers inject it inside their Broadway wrapper so that the actual subject sees the shared cache. Explicit snapshot artwork hooks and Duo fixtures receive that same actor. Ordinary production roots, standalone non-snapshot previews, and fresh-cache unit tests retain their ownership.

```mermaid
flowchart LR
    P["PreviewSupport: one snapshot path cache"] --> C["Snapshot declarations and helpers"]
    C --> V["Fresh views and artwork models"]
    V -->|"region + resolution"| A["RegionOutlinePathCache actor"]
    A --> G["Existing RegionKit geometry cache"]
    A -->|"cached Path value"| V
```

The actor stores deterministic geometry only. Each view still awaits and publishes its own artwork; cancellation cannot publish stale content. Diagram omits rendering and comparison, which do not change.

```swift
// Proposed composition, not a new production singleton.
extension PreviewSupport {
    static let snapshotArtworkCache = RegionOutlinePathCache()
}
// Apply the environment override inside the existing Broadway wrapper.
content.environment(\.regionOutlinePathCache, PreviewSupport.snapshotArtworkCache)
    .whereBroadwayRoot(theme: theme)
```

## Steps and acceptance

1. Record the unchanged five-suite baseline with `./test --no-generate --only WhereUISnapshotTests/AppearanceSettingsViewSnapshotTests --only WhereUISnapshotTests/LocationForecastSummarySnapshotTests --only WhereUISnapshotTests/LocationForecastPanelSnapshotTests --only WhereUISnapshotTests/LocationsBackgroundSnapshotTests --only WhereUISnapshotTests/RegionWelcomeCardSnapshotTests --timings --review --record never`.
2. Update snapshot composition and explicit snapshot cache consumers, including Duo fixtures. Keep the five post-settle hooks unchanged for this step.
3. Add hosted coverage for shared-cache injection through single and theme snapshot helpers, and independent publication state. Keep existing cache/model/task tests using fresh caches. Update the module README.
4. Run the same focused image matrix, plus the relevant WhereUI cache, artwork, and composition tests. Regenerate with `./ide --no-open` if adding source/test files.
5. Require no retries, unchanged identities/dimensions/tiles, passing references, and reviewed changed diagnostics. Record the observed cache-only delta without overstating it. Run architecture checks for the new composition boundary, formatting, and symbol lint. Commit this verified step.

Tests use `./test`; later snapshot invocations may use `--skip-host-tests` because the baseline owns applicable host checks. Full image integration in plan 02 covers the broad snapshot-helper injection. Restore only task-owned edits if a candidate fails.

## Execution record

Baseline running. No implementation changes yet.

## Resume point

Implement the shared cache after the baseline build completes; keep the built baseline products unchanged during its run.
