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
- Keep settings source testing and application in one exhaustive state. Carry
  the closed draft and its generation across every suspension before publishing success.
- Construct the live `ThrowSession`, stores, source graph, and poller only in
  `ThrowSession+Composition.swift`. Pass that session to every controller and output scene.
- Retain one launch task in the process session. Caller or scene cancellation
  must not cancel it.
- Start one durable logging task with the launch. Publish opening, ready, and
  failed storage as one typed state. Keep product launch independent of it.
- Leave loading only after preferences and both credential states load. Treat a
  missing credential as data and a credential access error as launch failure.
- Show localized recovery text for launch failures. Record the underlying error
  only in diagnostics.
- Route every root through `ThrowSessionLaunchState`. Create dashboard and
  projection surfaces only from its loaded cases.
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
- Publish the coordinator's complete state as one session value. Derive its
  public fields and the projection-output count instead of mirroring them.
- Give each playlist configuration a monotonic revision. Reject configurations
  that arrive after a newer revision.
- Keep coordinator command delivery lossless. Revalidate revision, demand,
  identity, and generation after each suspension before changing timer state.
- Require a successful response and a prepared frame from the same fresh target
  generation. Exchange that exact semantic/projected pair only at black. Buffer
  later target updates until fade-in completes, and never mix experiences.
- Send only `ProjectionExperienceInput` to the production projection worker.
  Keep raw layer-array entry points inside DEBUG test support.
- Build one closed `PreparedProjectionExperienceInput` after static-line
  projection. Never send the engine parallel semantic and projected arrays.
- Cache each typed static-line frame with its semantic revision and full
  projection context. Never rebuild or replace its projected payload by hand.
- Keep `ProjectedExperienceFrame` typed through the projection worker. Erase it
  only in `Projection/ProjectionFrame.swift`.
- Construct and replace raw `ProjectionFrame` and `ProjectedLayer` values only
  in `Projection/ProjectionFrame.swift`. Keep arbitrary test factories in DEBUG.
- Keep erased production frames in the closed Air & Space or Transit
  presentation case. Never animate across cases or combine a DEBUG frame with a
  production frame.
- Keep setup lifecycle data in the session's single `ThrowSetupState`. Change
  validated source and location values atomically through that state. Persist a
  replacement location before publishing it, and invalidate the old projection
  context before the new observer becomes visible.
- Put every preference write through the session's owned queue. Coalesce only
  adjacent UI snapshots, preserve immediate-write barriers, and flush the queue
  when the final controller scene backgrounds.
- Keep quiet-hours edits in a settings-scoped draft. Publish only a validated
  `QuietSchedule` to the session; invalid edits must leave runtime demand unchanged.
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
