# ThrowUI – Module Shape

ThrowUI is Throw's SwiftUI presentation layer; see [`README.md`](README.md).
Read the root [`AGENTS.md`](../../AGENTS.md) and group
[`../AGENTS.md`](../AGENTS.md) first.

## Scope and invariants

- Import ThrowCore and presentation dependencies only. Keep source adapters,
  persistence, projection math, polling, and credential access in ThrowCore.
- Use `AircraftSourceOperationServing` for source tests and usage reports.
  Never refer to a concrete provider source or decoder.
- Keep tested source candidates in `ValidatedAircraftSourceDraft`. Construct it
  only from a successful closed Core validation draft.
- Construct the live `ThrowSession`, stores, source graph, and poller only in
  `ThrowSession+Composition.swift`. Pass that session to every controller and output scene.
- Accept aggregate controller foreground presence from the app runtime. Do not
  observe application or UIKit scene lifecycle independently in ThrowUI.
- Keep aircraft behavior in the one injected `AirAndSpaceRuntime`. Keep
  selection, prewarming, and rotation in `ProjectionExperienceCoordinator`.
- Carry the coordinator-issued `ProjectionActivationLease` through activate and
  deactivate commands. Never mint a coordinator activation generation in a runtime.
- Invalidate superseded Air & Space lifecycle work after every suspension.
  Never let an old activation or deactivation change newer runtime state.
- Keep one coordinator timer across all scenes. Run at most the active and
  prewarming experience runtimes.
- Keep the coordinator playlist and active identity in one validated value.
  A nonempty playlist must always have an active identity from that playlist.
- Give each playlist configuration a monotonic revision. Reject configurations
  that arrive after a newer revision.
- Keep coordinator command delivery lossless. Revalidate revision, demand,
  identity, and generation after each suspension before changing timer state.
- Require a successful response and a prepared frame from the same fresh target
  generation. Exchange that frame only at black, and never mix experiences.
- Send only `ProjectionExperienceInput` to the production projection worker.
  Keep raw layer-array entry points inside DEBUG test support.
- Keep setup lifecycle data in the session's single `ThrowSetupState`. Change
  validated source and location values atomically through that state. Persist a
  replacement location before publishing it, and invalidate the old projection
  context before the new observer becomes visible.
- Put every preference write through the session's owned queue. Coalesce only
  adjacent UI snapshots, preserve immediate-write barriers, and flush the queue
  when the final controller scene backgrounds.
- Render projector, Preview, and full-screen fallback through
  `ProjectionSurface`. Do not add a parallel renderer.
- Keep the render loop on fixed deadlines. Skip elapsed frame slots instead of
  starting delayed work in a burst.
- Keep motion correction and its aggregate diagnostics inside the projection
  worker. Never log aircraft identities or coordinates.
- Draw cached Geography below marks in Map mode. Bound the static-line cache to
  recent projection keys. Keep Geography absent from True Sky, calibration,
  and quiet output.
- Iterate the layers supplied by `ProjectionFrame`. Do not restore catalog
  enumeration or a Geography special case in the surface.
- Keep external projection opaque black and free of interactive chrome.
- Pass `TemporaryQuietWake` values to quiet-wake intents. Never send raw minute
  counts from a view.
- Seed `ThrowStylesheet` with `throwBroadwayRoot()` at every independent root.
- Keep previews and snapshots on deterministic in-memory dependencies. Never
  access a live provider, GPS, UserDefaults, or Keychain.

## Testing

Run `./test ThrowUITests`. Image coverage lives in `ThrowUISnapshotTests` in
the shared `StuffSnapshotTests` scheme.
