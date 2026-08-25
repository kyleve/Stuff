# ThrowUI – Module Shape

ThrowUI is Throw's SwiftUI presentation layer; see [`README.md`](README.md).
Read the root [`AGENTS.md`](../../AGENTS.md) and group
[`../AGENTS.md`](../AGENTS.md) first.

## Scope and invariants

- Import ThrowCore and presentation dependencies only. Keep source adapters,
  persistence, projection math, polling, and credential access in ThrowCore.
- Keep one app-root-owned `ThrowSession`; pass it to every controller and
  output scene. A view or scene delegate must never create a second poller.
- Render projector, Preview, and full-screen fallback through
  `ProjectionSurface`. Do not add a parallel renderer.
- Draw cached Geography below marks in Map mode. Keep it absent from True Sky,
  calibration, and quiet output.
- Keep external projection opaque black and free of interactive chrome.
- Seed `ThrowStylesheet` with `throwBroadwayRoot()` at every independent root.
- Keep previews and snapshots on deterministic in-memory dependencies. Never
  access a live provider, GPS, UserDefaults, or Keychain.

## Testing

Run `./test ThrowUITests`. Image coverage lives in `ThrowUISnapshotTests` in
the shared `StuffSnapshotTests` scheme.
