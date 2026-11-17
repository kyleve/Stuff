# 02 — Skip pixel settling for synchronous measurement

- Status: executing
- Depends on: None; execute after the WebKit experiment releases the simulator.
- Shared context: [Overview](README.md)

## Deliverable and requirements

Use immediate measurement for fixtures whose complete height is synchronous.
This delivers US-01 and R-01–R-04 while preserving X-01–X-03.
Scope: RegionSummaryCard, FlightDayDetailView, and CalendarContentView's standalone MonthAccessibility fixture.
The full CalendarContentView remains unchanged: its mounted task changes content height.

## Evidence and design

RegionSummaryCard's supplied text and style determine its size. Artwork occupies backgrounds and a fixed stamp frame.
Move its path-cache preparation from measurement to `prepareForCapture`; retain final pixel settling.
FlightDayDetailView seeds its complete review synchronously. Its fixture report's scan is nil, so the mounted `receive(nil)` is a no-op.
MonthAccessibility supplies a complete value to MonthGridView and has no loading task.
No production data flow or architecture changes. Existing case properties express the different measurement policy.

```swift
// Existing APIs; only the fixture declaration changes.
whereThemeSnapshot(
    measurementReadiness: .immediate,
    prepareForCapture: { await warmFixedSizeArtwork() }
) { ExistingProductionCard() }
```

## Steps

1. Set explicit immediate measurement on the three supported fixture groups; document the height invariant beside the declarations.
2. Keep final settle modes, all configurations, native navigation, accessibility parsing, and references unchanged.
3. Run focused RegionSummaryCard, FlightDayDetailView, and CalendarContentView snapshots with timings and review, then compare identities and dimensions with PR #511.
4. Reject any candidate that changes sizing or content. Keep asynchronous Calendar cases on their current measurement policy.
5. Run the full image suite at the final stack tip, review independently, commit, and publish.

## Acceptance and recovery

All existing captures pass unchanged references; full-content heights and panel membership match.
Capture timers establish a reduction in intrinsic measurement. Final capture settling remains enabled.
Commands from repository root: `./test --no-generate --only WhereUISnapshotTests/RegionSummaryCardSnapshotTests --only WhereUISnapshotTests/FlightDayDetailViewSnapshotTests --only WhereUISnapshotTests/CalendarContentViewSnapshotTests --timings --review --record never`, then `./test --no-generate --snapshots --timings --record never` for integration.
On a failure, restore only the unsupported candidate and retain the evidence. Do not record new references.

## Review and progress

- 2026-11-16: Reviewed source, mounted tasks, geometry, test coverage, and scope at parent `f4e3b4c8c`.
- Q-01 resolved for these candidates; other measurement waits remain outside this deliverable.
- Pending: implementation, focused measurements, integration, independent review, and publication.

## Resume point

Run the focused profile for all three changed declarations, then compare capture identities, dimensions, and references.
