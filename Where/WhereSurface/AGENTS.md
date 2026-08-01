# WhereSurface – Module Shape

WhereSurface is the Foundation-only, read-only glance contract shared with
processes that must not open Where's store. See [`README.md`](README.md). This
file complements the root [`AGENTS.md`](../../AGENTS.md) and feature
[`Where/AGENTS.md`](../AGENTS.md).

## Scope & dependencies

- Depend only on Foundation/CoreFoundation; never import WhereCore, RegionKit,
  SwiftData, WidgetKit, SwiftUI, CloudKit, or location frameworks.
- Keep `WhereSurfaceStore` read-only. The Where app is the only writer of
  `widget-snapshot.json`.
- Carry presentation-ready names and ordering across the boundary; consumers
  never duplicate domain aggregation or region ranking.

## Invariants

- Keep `generatedAt` and `surface` optional in `WhereSurfaceDocument` so
  snapshots from older app versions decode.
- Coordinate every artifact read and atomic replacement through
  `WhereSurfaceFileCoordinator`.
- Treat `WhereSurfaceChangeNotification` as advisory and the JSON file as
  authoritative.
- Preserve the last successfully decoded payload when a later refresh fails.

## Testing

Swift Testing lives in [`Tests/`](Tests). Pin additive wire compatibility and
read behavior without resolving the real App Group container.
