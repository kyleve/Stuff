# Projection context transition

This model checks one question:

> Can Throw reject obsolete projection work and keep the invalidation gate closed until cleanup and authoritative lease synchronization finish?

The model represents the projection-context code at production commit
`60c25401`.

The model uses raw TLA+. Each action represents one suspension boundary or one
main-actor mutation. This form lets TLC insert invalidation and late completion
between independent worker, coordinator, cleanup, and animation actions.

Run the model from the repository root:

```sh
./tla-check ProjectionContextTransition
```

## Source correspondence

| Model state or action | Production authority |
| --- | --- |
| `context` | `projectionContextGeneration` in [`ThrowSession+Aircraft.swift`](../../ThrowUI/Sources/Model/ThrowSession+Aircraft.swift#L484-L510) |
| `inputRevision` | `projectionInputRevision` and the pending semantic frame in [`ThrowSession+Aircraft.swift`](../../ThrowUI/Sources/Model/ThrowSession+Aircraft.swift#L351-L405) |
| `coordinatorLease` | The lease from [`ProjectionExperienceCoordinator`](../../ThrowUI/Sources/Model/ProjectionExperienceCoordinator.swift#L408-L452) |
| `sessionLease` | The local `airAndSpaceActivation` lease, cleared during revoke and synchronized after configuration |
| `invalidationPhase` | The ordered invalidation work in the aircraft and observer publication paths |
| `staleCompletions` | Worker, report, or fade work that resumes after its context was revoked |
| `stagePhase` and staged fields | `ProjectionPresentationStaging` and `PreparedProjectionPresentation` |
| visible fields | The closed `ProjectionPresentationState` and `VisibleProjection` |
| worker completion and rejection actions | The two sides of `projectedOutput(...)` and its current-request guard in [`ThrowSession+Aircraft.swift`](../../ThrowUI/Sources/Model/ThrowSession+Aircraft.swift#L379-L405) |
| prepared report completion and rejection actions | The two sides of `reportRuntimePrepared(_:)` and its later guards in [`ThrowSession+Aircraft.swift`](../../ThrowUI/Sources/Model/ThrowSession+Aircraft.swift#L406-L424) |
| fade and coordinator commit actions | The awaits in [`transitionExperience(from:to:)`](../../ThrowUI/Sources/Model/ThrowSession+Experiences.swift#L295-L420) |
| `CommitCurrentPreparedPair` | The single black-frame exchange in [`publishPreparedProjection`](../../ThrowUI/Sources/Model/ThrowSession+Experiences.swift#L438-L457) |
| `UpdateTargetInput` | A newer runtime update buffered by `ProjectionPresentationStaging` |
| `InvalidateProjectionContext` | Context, stage, local lease, and renderer revoke in [`prepareProjectionPreferencePublication`](../../ThrowUI/Sources/Model/ThrowSession+Aircraft.swift#L484-L510) |
| `RenewExactActivationLease` | The exact active renewal await in [`finishProjectionPreferenceInvalidation`](../../ThrowUI/Sources/Model/ThrowSession+Aircraft.swift#L513-L533) |
| `DrainOldRuntime` | Old-lease runtime deactivation in [`finishProjectionPreferenceInvalidation`](../../ThrowUI/Sources/Model/ThrowSession+Aircraft.swift#L534-L540) |
| `CompleteObserverOrSourceCleanup` | Observer worker reset or aircraft [`discardOldFrame`](../../ThrowUI/Sources/Model/ThrowSession+Aircraft.swift#L1065-L1097) |
| `ConfigureCoordinator`, `ReadCoordinatorState`, and `SynchronizeAuthoritativeLease` | Three awaits and the local synchronization in [`configureExperienceCoordinator`](../../ThrowUI/Sources/Model/ThrowSession+Experiences.swift#L232-L240) |
| `FinishInvalidation` | The identity checks and gate removal in [`completeProjectionPreferenceInvalidation`](../../ThrowUI/Sources/Model/ThrowSession+Aircraft.swift#L550-L562) |
| `CompleteFadeIn` | Buffered publication in [`finishProjectionPresentationTransition`](../../ThrowUI/Sources/Model/ThrowSession+Experiences.swift#L460-L473) |

Every modeled production `await` ends one action. Another enabled action can
run before the next action begins. Task cancellation does not complete pending
work in the model.

Worker revision equality represents `output.request == currentRequest`. Report
revision equality represents the later prepared-value identity check.

The observer path clears visible content during context revoke. Its cleanup
phase completes after the worker reset. The aircraft path completes cleanup
after old-frame removal and worker reset.

## Invalidation phases

The model keeps these phases separate and ordered:

1. Revoke the context, staged presentation, local lease, and renderer.
2. Renew the exact active coordinator lease.
3. Drain the runtime that used the old lease.
4. Finish observer or aircraft cleanup.
5. Configure the coordinator.
6. Read the coordinator state.
7. Synchronize the local lease with the authoritative lease.
8. Remove the invalidation gate.

A stale worker, report, or fade can complete between any two phases. Each stale
completion consumes only its pending token. It cannot restore staged or visible
content.

## Operational lease abstraction

`NoLease` means that no operational writer or marks use a lease. It does not
mean that every Swift value contains empty lease metadata.

[`VisibleProjection.cleared`](../../ThrowUI/Sources/Projection/VisibleProjection.swift#L356-L368)
keeps the old lease metadata in a placeholder. That placeholder has no marks
and gives no runtime permission. The model represents this state as
`visibleLease = NoLease`.

## Properties

- `TypeOK` checks every variable domain.
- `StagingShape` checks the closed staging lifecycle.
- `OperationalVisibleIdentity` binds operational visible content to both lease authorities.
- `ExactVisiblePair` requires matching semantic and projected revisions.
- `NoInvalidatedContextCommit` rejects a black commit from an invalid context.
- `NoMismatchedCommit` rejects the old mixed-revision commit design.
- `NoStaleInputAcceptance` rejects worker or report output for an older input revision.
- `NoWriterDuringFadeIn` keeps runtime writers out of the fade-in phase.
- `InvalidationGateHoldsUntilCleanupAndLeaseSync` keeps the gate closed through every required phase.
- `RequiredPathsNotAllReached` is the main anti-vacuity probe.
- Five focused probes check the three late completions and both freshness rejections.

The main reachability trace visits preparation, a black commit, a buffered
revision, both invalidation sites, and all seven gated work phases.

## Bounds and assumptions

| Configuration | Context changes | Later input revisions | Activation leases |
| --- | ---: | ---: | ---: |
| `CurrentSmall.cfg` | 1 | 1 | 2 |
| `CurrentLarger.cfg` | 2 | 2 | 3 |

The model uses these assumptions:

- One target projection can be staged at a time.
- Source and observer changes use the same invalidation gate.
- The checked renewal replaces one exact active Air and Space lease.
- Lease generations increase within each finite configuration.
- The coordinator lease and the session lease remain separate authorities.
- Environment actions can resume stale worker, report, and fade work in any invalidation phase.
- Cleanup success has one atomic completion action after its internal awaits.

The model checks safety only. It has no fairness rule. It does not require a
timer, provider, worker, coordinator, or animation callback to return.

The model excludes invalidation without an active lease. It also excludes
retired and superseded renewal results. Coordinator tests cover those results.
The model excludes cleanup failure details after the source selects its
clear-state recovery.

Other exclusions include projection math, pixels, route enrichment, polling,
playlist policy, preference persistence, and application scene admission.

## Negative controls

`BrokenContext.cfg` keeps staged work during invalidation. It also omits the
current context and lease checks. TLC finds this nine-state trace:

1. The worker prepares context 0 with lease 1.
2. The presentation reaches the coordinator commit boundary.
3. Invalidation advances the context to 1 and clears the session lease.
4. The old prepared frame commits at black.
5. `NoInvalidatedContextCommit` fails.

`BrokenPair.cfg` reproduces the old mixed-frame shortcut. A later semantic
revision arrives while the coordinator commit suspends. The black exchange
combines semantic revision 1 with projected revision 0. `ExactVisiblePair`
fails after nine states.

`BrokenFreshness.cfg` accepts a worker result for an older input. Input revision
1 replaces revision 0 while its worker is suspended. The old result resumes
and becomes prepared. `NoStaleInputAcceptance` fails after four states.

`BrokenWriter.cfg` publishes a buffered update during fade-in. TLC reaches the
write after ten states. `NoWriterDuringFadeIn` then fails.

`BrokenEarlyInvalidationFinish.cfg` removes the gate after runtime drain. It
skips cleanup, coordinator configuration, state read, and lease synchronization.
`InvalidationGateHoldsUntilCleanupAndLeaseSync` fails after five states.

These controls use the current state variables and the same named safety
properties. The `BrokenContext`, `BrokenPair`, and `BrokenWriter` controls
preserve their prior source event timelines.

## Reachability controls

`Reachability.cfg` reaches every main lifecycle flag after 19 states. The
three stale controls also produce direct traces:

- A worker resumes after context revoke in four states.
- A prepared report resumes after context revoke in six states.
- A fade resumes after context revoke in eight states.
- A superseded worker result reaches its rejection in four states.
- A superseded prepared report reaches its rejection in six states.

Each late-completion trace leaves staging empty and keeps the invalidation gate
active. Each freshness trace leaves staging empty during normal operation.

## Result

**Verified for these model bounds and assumptions.** TLC exhausted both current
configurations with no error.

| Configuration | Result | Generated | Distinct | Depth |
| --- | ---: | ---: | ---: | ---: |
| `CurrentSmall.cfg` | pass | 5,556 | 3,491 | 41 |
| `CurrentLarger.cfg` | pass | 102,734 | 45,101 | 57 |
| `BrokenContext.cfg` | expected failure | 162 | 96 | 9 |
| `BrokenPair.cfg` | expected failure | 104 | 81 | 9 |
| `BrokenFreshness.cfg` | expected failure | 15 | 13 | 4 |
| `BrokenWriter.cfg` | expected failure | 140 | 109 | 10 |
| `BrokenEarlyInvalidationFinish.cfg` | expected failure | 35 | 28 | 5 |
| `Reachability.cfg` | expected failure | 1,554 | 1,000 | 19 |
| `StaleWorkerReachability.cfg` | expected failure | 17 | 15 | 4 |
| `StaleReportReachability.cfg` | expected failure | 41 | 32 | 6 |
| `StaleFadeReachability.cfg` | expected failure | 80 | 63 | 8 |
| `WorkerInputRejectionReachability.cfg` | expected failure | 14 | 13 | 4 |
| `ReportInputRejectionReachability.cfg` | expected failure | 38 | 30 | 6 |

The check used tla2tools 1.7.4 with TLC2 2.19 at revision `5a47802`. It used
Temurin Java 21.0.8+9. The pinned `tla2tools.jar` SHA-256 is
`936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88`.

Deterministic Swift guards:

- [`ThrowSessionExperiencesTests.blackCommitKeepsPreparedIdentityAndRevisionAheadOfBufferedInput`](../../ThrowUI/Tests/ThrowSession+ExperiencesTests.swift#L8)
- [`ThrowSessionExperiencesTests.contextInvalidationWhileRuntimePreparationSuspendsRejectsThePreparedOutput`](../../ThrowUI/Tests/ThrowSession+ExperiencesTests.swift#L201)
- [`ThrowSessionExperiencesTests.contextInvalidationDuringFadeRevokesTheBlackCommit`](../../ThrowUI/Tests/ThrowSession+ExperiencesTests.swift#L276)
- [`ThrowSessionAircraftTests.samePermitSourceReconfigurationRenewsLeaseAndPhysicalPoller`](../../ThrowUI/Tests/ThrowSession+AircraftTests.swift#L130)
- [`ProjectionExperienceCoordinatorTests.exactActiveRenewalRetiresAndRemintsInOneCoordinatorTurn`](../../ThrowUI/Tests/ProjectionExperienceCoordinatorTests.swift#L91)

A change to the listed production boundaries invalidates this result. Check
the mapping and rerun TLC after such a change.
