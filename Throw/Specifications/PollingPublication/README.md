# Polling publication

This model checks one question:

> After Throw replaces aircraft polling, can an old or out-of-order update become the new activation's visible state?

The model represents production commit `cf153cf6aae65f9d9177897adf5d543d81656a29`.
That commit added ordered polling publications and strict revision acceptance.

This result is design evidence for the stated bounds and assumptions.
It is not proof that the Swift implementation is correct.
Relevant source changes invalidate this result until the mapping is checked again.

The tracked module contains only PlusCal source.
`./tla-check` translates a copy in its retained run directory.
Do not run `pcal.trans` on the tracked file.

Run this concern from the repository root:

```sh
./tla-check PollingPublication
```

## Source correspondence

| Model state or action | Production authority |
| --- | --- |
| `targetContext` | `AirAndSpaceRuntime.activePollingSignature` identifies the requested source and query. |
| `mintedToken` | `AircraftPollingCoordinator.activate(...)` and `update(...)` mint a typed token from `lifecycleRequestGeneration`. |
| `coreToken` and `coreContext` | `AircraftPollingCoordinator.activePolling` owns the accepted token, configuration, and query. |
| `coreRevision` | `AircraftPollingCoordinator.activePublicationRevision` orders publications within one token. |
| `coreUpdate` | The coordinator's private `update` field is the value returned by `currentUpdate()`. |
| `sourcePhase` and `PublishHealthySnapshot` | The poll task returns from `snapshot(for:)`, checks its generation, and calls `publish(...)`. |
| `streamBuffer` | The coordinator's `AsyncStream` uses `.bufferingNewest(1)`. A new yield replaces the pending value. |
| `streamDelivery` | The observation task has received a value, but `AirAndSpaceRuntime.apply(...)` has not run. |
| `recoveryUpdate` | `currentUpdate()` captured Core state before the activation task resumed on the runtime actor. |
| `acceptance` | `PollingPublicationAcceptance` is inactive, awaiting activation, or active with one token and revision cursor. |
| `lastConsumed` | The last active update that passed `PollingPublicationAcceptance.accept(...)`. |
| `stateGeneration` | `AirAndSpaceRuntime.stateGeneration` invalidates semantic work started from older state. |
| `pendingFrames` and `CompleteFrame` | `makeLayerFrame(...)` is suspended, or its result has returned to the runtime actor. |
| `uiState` and content fields | `health`, `currentSnapshot`, and `currentLayerFrame` supply the published runtime update. |

The production sources are
[`AircraftPollingCoordinator.swift`](../../ThrowCore/Sources/AircraftPollingCoordinator.swift)
and [`AirAndSpaceRuntime.swift`](../../ThrowUI/Sources/Model/AirAndSpaceRuntime.swift).

The model separates each relevant suspension or delivery boundary:

1. `BeginNextOperation` clears the expected token and presentation before replacement work.
2. `ResetOrQueryBoundary` represents the frame reset suspension for a new source or lease.
3. The same label marks the direct coordinator path for a query-only change that skips the reset.
4. `CoordinatorMintsToken` runs before the queued lifecycle operation replaces the old poller.
5. `CoreBeginReplacement` publishes inactive, cancels the old task, and starts its drain.
6. `CoreDrainOldPoller` resumes after `oldTask.value`, accepts the new token, and publishes loading revision 1.
7. `CoordinatorReturnsToken` and `InstallExpectedToken` are the two sides of the cross-actor call.
8. `CaptureCurrentUpdate` and `ApplyCurrentUpdate` are the two sides of the recovery call.
9. `TakeBufferedUpdate` receives one stream value before `ApplyStreamUpdate` enters the runtime actor.
10. `PublishHealthySnapshot` represents a source result returning while its token is still current.
11. `CompleteFrame` represents the route-cache and frame-builder suspensions returning.
12. The three deactivation labels cover Core cancellation, drain, and the runtime frame reset.

The token is also the abstract context identifier.
Distinct tokens therefore represent distinct source or query state.
This abstraction preserves the identity comparison required by the checked property.

The `update` operation represents a query-only replacement that skips `flightsRuntime.reset()`.
It also covers the shared Core `performUpdate(...)` to `replace(...)` path.
No production caller invokes `AircraftPollingCoordinator.update(...)` at this source revision.

## Properties

- `TypeOK` checks every variable domain.
- `AcceptanceShape` checks the closed inactive, awaiting, and active acceptance forms.
- `CorePublicationShape` binds Core's current update, token, context, state, and revision.
- `ExactTokenAcceptanceSafety` rejects every active update from another context.
- `ExactTokenPublicationSafety` rejects a healthy state or visible frame from another context.
- `AcceptedRevisionsNeverRegress` requires strict revision growth within an accepted token.
- `CorrectAtQuiescence` requires Core, acceptance, health, and visible content to agree after all work drains.
- `EventuallyConverges` requires that agreement after the finite lifecycle plan finishes.

Every current configuration also checks deadlock freedom.
The explicit quiescent action models a live process after finite work settles.

## Reachability

Expected-failure reachability cases prove that TLC visits these required branches:

- An old update is buffered or in flight when a replacement begins.
- The current design rejects an old-token delivery.
- A new-token update arrives before the runtime installs that token.
- `currentUpdate()` recovers an update that the one-slot stream lost or rejected.
- A newer stream update overtakes an older recovery capture.
- The revision cursor rejects that older recovery capture.
- A new activation invalidates an older frame build.
- Deactivation applies the closed inactive update.
- The query-update path runs.

These controls prevent a clean result that avoids the important races.

## Bounds, fairness, and exclusions

The initial state has active token 1 and loading revision 1.
The stream buffer also holds that update, and token 1 has one pending source result.

The current configurations exhaust these finite plans:

- `CurrentSingle.cfg` replaces context 1 with context 2 through an activation.
- `CurrentUpdate.cfg` replaces context 1 with context 2 through a query update.
- `CurrentRepeated.cfg` activates context 2, then updates to context 3.
- `CurrentDeactivation.cfg` activates context 2, then deactivates it.

Each active token publishes loading revision 1 and at most one healthy revision 2.
The stream has one pending slot and one independent delivery in flight.
Frame completion order is unrestricted.

Weak fairness makes the finite lifecycle plan progress.
It also schedules a continuously enabled source, observer, recovery, and frame completion.
These assumptions match the progress required for `EventuallyConverges`.

The source fairness assumption means that the final active source returns one healthy result.
A provider can hang indefinitely in production.
The liveness result does not cover that behavior.
The safety properties do not require source completion.

The model excludes source failures, retries, quiet state, task cancellation, and process termination.
It also excludes route enrichment, frame-builder failure, and provider polls after the first healthy result.
The separate `ProjectionActivation` model covers overlapping lifecycle commands and lease tombstones.

The model assumes finite counters do not overflow.
It assumes a Core update caller installs the returned token before it applies recovery state.
The bounded plans do not cover an independent caller that discards that token.

## Historical controls

`BrokenLeaseLess.cfg` models the state before commit `6492d2d5`.
That design streamed bare polling state and had no activation token.
TLC finds this trace:

1. Context 2 begins and clears its visible content while reset is suspended.
2. The source for context 1 publishes its healthy result.
3. The observation task receives that old result.
4. The token-less runtime consumes context 1 state as context 2 state.
5. `ExactTokenPublicationSafety` fails at depth 5.

`BrokenRevisionLess.cfg` models commit `6492d2d5` before the ordered envelope.
That design checked exact tokens and unequal states, but it had no publication cursor.
TLC finds this trace:

1. `currentUpdate()` captures token 2 loading state.
2. Token 2 healthy state reaches the stream and starts a frame build.
3. The older loading capture resumes and passes the unequal-state check.
4. Loading increments `stateGeneration` and invalidates the healthy frame.
5. The buffer drains while Core remains healthy and the runtime remains loading.
6. `CorrectAtQuiescence` fails at depth 16.

Both controls use a property that every current configuration checks.
The manifest requires the named failure, so another TLC error does not count.

The deterministic Swift guard is
[`AirAndSpaceRuntimeTests.currentUpdateRecoveryCannotRegressANewerStreamPublication`](../../ThrowUI/Tests/AirAndSpaceRuntimeTests.swift).
It parks the recovery capture and the healthy frame build without timing delays.

## Result

**Verified for these model bounds and assumptions.**

TLC exhausted all current state spaces without an invariant, temporal, or deadlock error.
Both historical controls failed for the mapped reason.
All reachability controls reached their required branch.

| Configuration | Result | Generated | Distinct | Depth |
| --- | ---: | ---: | ---: | ---: |
| `BrokenLeaseLess.cfg` | expected failure | 40 | 27 | 5 |
| `BrokenRevisionLess.cfg` | expected failure | 1,381 | 805 | 16 |
| `OldInFlightReachability.cfg` | expected failure | 2 | 2 | 2 |
| `OldRejectionReachability.cfg` | expected failure | 17 | 14 | 4 |
| `EarlyUpdateReachability.cfg` | expected failure | 100 | 67 | 8 |
| `RecoveryReachability.cfg` | expected failure | 178 | 116 | 10 |
| `OvertakeReachability.cfg` | expected failure | 539 | 329 | 13 |
| `StaleFrameReachability.cfg` | expected failure | 66 | 44 | 6 |
| `InactiveReachability.cfg` | expected failure | 807 | 486 | 14 |
| `UpdateReachability.cfg` | expected failure | 5 | 5 | 3 |
| `CurrentSingle.cfg` | pass | 3,393 | 1,705 | 23 |
| `CurrentUpdate.cfg` | pass | 3,393 | 1,705 | 23 |
| `CurrentRepeated.cfg` | pass | 79,350 | 30,644 | 37 |
| `CurrentDeactivation.cfg` | pass | 11,639 | 5,588 | 29 |

The check used tla2tools 1.7.4, TLC2 2.19 at revision `5a47802`, and PlusCal 1.11.
It used Eclipse Temurin Java 21.0.8+9.
The pinned JAR SHA-256 is
`936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88`.

Changes to token minting, publication revision, buffering, acceptance, recovery, or frame invalidation require a new check.
