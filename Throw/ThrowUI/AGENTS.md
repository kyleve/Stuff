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
- Keep onboarding source selection, the exact tested draft, validation, and any
  staged credential in one exhaustive state. Derive presentation status from it.
- Keep settings source testing and application in one exhaustive state. Carry
  the closed draft and its generation across every suspension before publishing success.
- Construct the live `ThrowSession`, stores, source graph, and poller only in
  `ThrowSession+Composition.swift`. Pass that session to every controller and output scene.
- Retain one launch task in the process session. Caller or scene cancellation
  must not cancel it.
- Start one durable logging task with the launch. Publish opening, ready, and
  failed storage as one typed state. Keep product launch independent of it.
- Inject one durable-logging starter into the session. Derive the session,
  Air & Space, and projection-worker failure logger from that starter.
- Leave loading only after preferences and both credential states load. Treat a
  missing credential as data and a credential access error as launch failure.
- Show localized recovery text for launch failures. Record the underlying error
  only in diagnostics.
- Represent software attribution as loaded credits or a failed state. Keep a
  loaded empty report distinct from manifest failure.
- Pass attribution-load errors into the durable-logging starter. Never show the
  underlying error in UI.
- Store post-launch failures in `ThrowPostLaunchFailureLedger`. Keep one failure
  per owner, and clear only the owner whose operation succeeds.
- Show localized recovery text for post-launch failures. Attach each caught
  underlying error to its typed `ThrowSessionLogEvent`.
- Route every root through `ThrowSessionLaunchState`. Create dashboard and
  projection surfaces only from its loaded cases.
- Accept aggregate controller foreground presence from the app runtime. Do not
  observe application or UIKit scene lifecycle independently in ThrowUI.
- Keep aircraft behavior in the one injected `AirAndSpaceRuntime`. Keep
  selection, prewarming, and rotation in `ProjectionExperienceCoordinator`.
- Carry the coordinator-issued `ProjectionActivationLease` through activate and
  deactivate commands. Never mint a coordinator activation generation in a runtime.
- Store a matching activation lease in each production rendered projection.
  Block local reactivation while a source or observer replacement drains.
- Invalidate superseded Air & Space lifecycle work after every suspension.
  Never let an old activation or deactivation change newer runtime state.
- Keep one coordinator timer across all scenes. Run at most the active and
  prewarming experience runtimes.
- Keep the coordinator playlist and active identity in one validated value.
  A nonempty playlist must always have an active identity from that playlist.
- Store coordinator identity, activation generation, semantic input, rendered
  frame, effects, observer point, and Geography health in one
  `ProjectionPresentationState`. Derive all public presentation fields from it.
- Give each playlist configuration a monotonic revision. Reject configurations
  that arrive after a newer revision.
- Keep coordinator command delivery lossless. Revalidate revision, demand,
  identity, and generation after each suspension before changing timer state.
- Require a successful response and prepared output from the same fresh target
  generation. Bind both to one source and observer context. Keep preparation
  and fade in one staging value. Recheck its context after preparation and at
  black. Buffer later target updates until fade-in completes.
- Send only `ProjectionFrameRequest` to the production projection worker. Keep
  raw layer-array entry points inside DEBUG test support.
- Publish a worker result only when its typed request still matches the current
  semantic revision and complete projection context.
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
- Advance the typed projection-context generation before a source or observer
  replacement becomes visible. Revoke staged output and restore an active fade
  in the same synchronous operation.
- Keep source and location projections getter-only. Change them through their
  persisted session command, except for DEBUG Testing SPI fixture methods.
- Keep the preference worker, queued requests, active mutation, deferred
  failures, and flush waiters in one exhaustive persistence state.
- Coalesce only adjacent UI snapshots, and preserve immediate-write barriers.
  A preference flush completes only when the persistence state is idle.
- Keep final-background task and UIKit execution-lease ownership in the app
  runtime. ThrowUI reports quiescence and does not start lifecycle tasks.
- Build immediate source and location commits from the complete typed preference
  snapshot. Re-persist the snapshot after drift. Publish it without another
  suspension.
- After the first durable source or location write, report the transaction as
  committed. Preserve newer typed edits and queue them after a retry failure.
- After a source write commits, do not restore its credential.
- Store session preferences as validated global and experience aggregates.
  Expose scalar display values as read-only projections.
- Keep raw control values inside their view or model. Validate a complete
  replacement before publication. Invalid drafts must not save or reconcile demand.
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
