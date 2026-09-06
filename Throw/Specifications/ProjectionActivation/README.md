# Projection activation

This model checks one question:

> Does Throw preserve the correct experience lease while context and physical polling demand change, without allowing stale work to regain authority?

The model represents production commit
`32f5f22fe8bf335133bc5bc465c6de0c4322cf72`.

The tracked source contains only PlusCal. `./tla-check` translates it in the
retained run directory. Do not run `pcal.trans` directly.

Run the model from the repository root:

```sh
./tla-check ProjectionActivation
```

## Source correspondence

| Model state or action | Production authority |
| --- | --- |
| `foregroundScenes` | [`ThrowRuntime.controllerScene(_:didReceive:)`](../../Throw/Sources/ThrowRuntime.swift) owns aggregate controller-scene foreground presence. |
| `connectedOutputs` and calibration events | [`ThrowSession.projectionOutputConnected(_:)`, `projectionOutputDisconnected(_:)`, and `updateCalibrationState()`](../../ThrowUI/Sources/Model/ThrowSession.swift) own output demand and calibration. |
| `quietRequested` | [`ThrowSession+Quiet.swift`](../../ThrowUI/Sources/Model/ThrowSession+Quiet.swift) schedules demand changes at quiet boundaries. |
| `pollingBlocked` | Session-only blockers in [`reconcileDemand(generation:)`](../../ThrowUI/Sources/Model/ThrowSession+Aircraft.swift) stop physical polling without changing coordinator permission. |
| `requestRevision` and `capturedRevision` | [`ProjectionDemandGeneration`](../../ThrowUI/Sources/Model/ThrowSession.swift) and `scheduleDemandReconciliation()` coalesce session demand. |
| `RawPermit` | Raw scene, output, quiet, and calibration inputs supplied by `ThrowSession`. |
| `reconciledPermit` | [`ProjectionExperienceDemand.permitsProjection`](../../ThrowUI/Sources/Model/ProjectionExperienceCoordinator.swift) is the last demand accepted by the coordinator. |
| `coordinatorLease` and `issuedLeases` | `activateRuntime(_:role:)` is the only lease issuer in `ProjectionExperienceCoordinator.swift`. |
| `invalidationPhase` | [`prepareProjectionPreferencePublication(_:)`, `finishProjectionPreferenceInvalidation(_:)`, and `completeProjectionPreferenceInvalidation(_:)`](../../ThrowUI/Sources/Model/ThrowSession+Aircraft.swift) keep the invalidation gate active through replacement. |
| `RenewExactCoordinatorLease` | [`renewActivationLease(_:)`](../../ThrowUI/Sources/Model/ProjectionExperienceCoordinator.swift) retires one exact running lease and can mint a successor atomically. |
| `actionQueue` | The coordinator action stream and [`applyExperienceCoordinatorAction(_:)`](../../ThrowUI/Sources/Model/ThrowSession+Experiences.swift) form one FIFO action lane. |
| `SynchronizeCurrentLease` | [`reconcileExperienceDemand(isQuiet:)`](../../ThrowUI/Sources/Model/ThrowSession+Experiences.swift) reads the authoritative optional running lease in both directions. |
| `SynchronizeSuccessorWhileGated` | [`configureExperienceCoordinator(with:)`](../../ThrowUI/Sources/Model/ThrowSession+Experiences.swift) installs the successor before `completeProjectionPreferenceInvalidation(_:)` opens the gate. |
| `sessionLease` | [`ProjectionActivationLeaseTracker`](../../ThrowUI/Sources/Model/ProjectionExperienceCoordinator.swift) has active and equality-tombstoned inactive states. |
| `demandQueue` | Calls from demand tasks can reach `AirAndSpaceRuntime` in either order before actor admission. Each call carries `ProjectionDemandGeneration`. |
| `runtimeLease` and `latestRuntimeLease` | [`AirAndSpaceRuntime.ActivationLifecycle`](../../ThrowUI/Sources/Model/AirAndSpaceRuntime.swift) owns active experience authority and its monotonic tombstone. |
| `pollDemandState` and `pollDemandGeneration` | [`AirAndSpaceRuntime.PollingDemandLifecycle`](../../ThrowUI/Sources/Model/AirAndSpaceRuntime.swift) owns physical polling, stopped demand, and its equality tombstone. |
| `pollRequestRevision` | One model revision identifies each runtime-minted physical polling attempt. Production uses `AirAndSpacePhysicalPollingLease`. |
| `pollQueue` and poll phases | [`AircraftPollingCoordinator`](../../ThrowCore/Sources/AircraftPollingCoordinator.swift) serializes lifecycle work through `lifecycleTail`. |
| `DrainPhysicalPoller` and `StartPhysicalPoller` | Core cancels and drains the old task before a current request starts a replacement. |

`RawPermit` is requested coordinator permission. `reconciledPermit` is accepted
coordinator permission. The model keeps these facts separate while work is
pending.

`pollingBlocked` is requested session-only suspension. It abstracts flights
disabled, no enabled layer, a non-operational launch, and unavailable polling
inputs. It does not retire the coordinator lease.

`contextChange` abstracts a committed aircraft-source or observer-location
change. Preparation tombstones the session lease and closes the gate. The
coordinator then renews the exact running lease. Runtime retirement completes
before the successor synchronizes. The gate opens after synchronization.

Each labeled PlusCal action represents one atomic region or one suspension
boundary. The coordinator action lane stays FIFO. The physical demand lane can
overtake before actor admission, as Swift tasks can suspend before an actor
call. Runtime state rejects stale work after admission.

## Properties

- `TypeOK` checks every variable domain.
- `OwnershipUsesIssuedLeases` rejects experience authority not minted by the coordinator.
- `NoStaleTeardownOfNewerLease` rejects a teardown generation older than its victim.
- `AtMostOnePhysicalPoller` limits the physical poller set to one.
- `SessionLeaseMatchesHighWater` makes an active session lease equal its generation high-water mark.
- `RuntimeLeaseMatchesHighWater` makes an active runtime lease equal its generation high-water mark.
- `PermitSafety` allows a poller without requested physical permission only while current reconciliation or teardown remains pending.
- `CorrectAtQuiescence` requires requested and reconciled permission, leases, physical demand, and the poller to agree.
- `FreshContextAtQuiescence` requires a same-permit context change to converge on a lease and physical attempt newer than the retired context.
- `FreshPhysicalResumeAtQuiescence` requires polling to resume with a newer physical attempt under the preserved experience lease.
- `EventuallyConverges` requires quiescent agreement after all finite events finish.

Reachability controls prove that TLC visits these states:

- Requested and reconciled coordinator permission differ.
- Permission loss has a pending physical teardown.
- Direct synchronization reads the current optional coordinator lease.
- A stale teardown waits behind a newer session lease.
- Runtime installs a newer experience tombstone.
- Physical replacement drains an existing poller.
- A physical poller starts.
- Two controller scenes overlap.
- Quiet time and calibration block coordinator permission.
- A context invalidation gate closes, renews an exact lease, synchronizes it while gated, and starts its replacement poller.
- A delayed old activation runs before and after the gate opens following successor synchronization.
- An accepted old teardown resumes after the successor runtime starts.
- A session-only suspension drains a poller and resumes the same lease with a new attempt.
- A delayed older activation reaches runtime after a newer stopped demand.

## Bounds, fairness, and exclusions

Current cases use these finite event plans:

- `LeaseReplacementRace` uses one scene, one output, and four events.
- `TwoSceneOverlapEvents` uses two scenes, one output, and five events.
- `ContextRenewalEvents` uses one scene, one output, and three events.
- `PhysicalSuspensionEvents` uses one scene, one output, and four events.
- `ContextAndSuspensionEvents` uses one scene, one output, and five events.

The reachability cases also use seven-event single-scene and twelve-event
two-scene plans. These cases stop at the first reached witness.

The finite environment eventually submits each configured event. Each enabled
reconciliation, invalidation, action, runtime, demand, and Core lane eventually
takes a step. These fairness assumptions support `EventuallyConverges`.

The model assumes one available Air & Space experience. It models the exact
active-runtime renewal path. Swift tests cover requested, prewarming, and
transition renewal outcomes.

The model assumes that context transactions are serialized. A context event
represents a successful preference commit. Persistence rollback is outside the
protocol.

One `contextChange` event combines the preparation and final demand-generation
bumps. The closed gate prevents demand application between those production
bumps.

The model combines all session-only polling blockers into one Boolean. It does
not distinguish geography rendering from launch, source, credential, GPS, or
query readiness.

The model checks lifecycle ownership, not provider publications. The separate
`PollingPublication` model checks token and publication-revision ordering.

The model excludes provider failures, network results, projection math,
rendering, preference staging, process termination, playlist rotation details,
and infinite event streams.

## Negative controls

`BrokenIdentityTeardown.cfg` models teardown by experience identity. A delayed
lease 1 command clears session lease 2. `NoStaleTeardownOfNewerLease` fails at
depth 18.

`PreFixStoppedLease.cfg` exposes a stopped coordinator lease and permits an
inactive equality resurrection. `CorrectAtQuiescence` fails at depth 20.

`PreFixRuntimeTombstone.cfg` omits the inactive runtime tombstone. A delayed
lease 1 activation starts after lease 2 teardown. `PermitSafety` fails at depth
19.

`PreFixContextRetainedLease.cfg` keeps lease 1 during a same-permit context
change. The session and runtime tombstone lease 1. Direct synchronization
cannot reactivate the equal lease. `FreshContextAtQuiescence` fails at depth
17.

`PreFixPollingRetiresLease.cfg` uses full experience deactivation for a
session-only stop. The coordinator keeps lease 1, but runtime tombstones it.
The later enabled demand cannot resume lease 1. `CorrectAtQuiescence` fails at
depth 17.

`PreFixNoDemandTombstone.cfg` ignores a stopped demand while runtime is stopped.
The held generation 2 activation then enters after generation 3 stopped demand
and starts a poller. `PermitSafety` fails at depth 16.

Each control uses the same state and current-design property that it must
falsify. The manifest requires the named failure. Another error does not count
as a successful control.

## Result

**Verified for these model bounds and assumptions.** TLC exhausted every
current configuration with no invariant, temporal, or deadlock error.

| Configuration | Result | Generated | Distinct | Depth |
| --- | ---: | ---: | ---: | ---: |
| `CurrentRace.cfg` | pass | 6,769 | 2,871 | 30 |
| `CurrentTwoScenes.cfg` | pass | 3,583 | 1,592 | 29 |
| `CurrentContextRenewal.cfg` | pass | 2,095 | 1,066 | 28 |
| `CurrentPhysicalSuspension.cfg` | pass | 1,629 | 681 | 27 |
| `CurrentContextAndSuspension.cfg` | pass | 82,983 | 29,182 | 44 |
| `BrokenIdentityTeardown.cfg` | expected failure | 1,238 | 546 | 18 |
| `PreFixStoppedLease.cfg` | expected failure | 11,742 | 4,350 | 20 |
| `PreFixRuntimeTombstone.cfg` | expected failure | 11,087 | 4,100 | 19 |
| `PreFixContextRetainedLease.cfg` | expected failure | 408 | 235 | 17 |
| `PreFixPollingRetiresLease.cfg` | expected failure | 846 | 368 | 17 |
| `PreFixNoDemandTombstone.cfg` | expected failure | 740 | 316 | 16 |
| `PermitGapReachability.cfg` | expected failure | 7 | 5 | 4 |
| `PermitTeardownReachability.cfg` | expected failure | 466 | 211 | 11 |
| `DirectLeaseSyncReachability.cfg` | expected failure | 36 | 22 | 6 |
| `RaceReachability.cfg` | expected failure | 1,238 | 546 | 18 |
| `PhysicalReachability.cfg` | expected failure | 315 | 147 | 10 |
| `RuntimeTombstoneReachability.cfg` | expected failure | 881 | 386 | 13 |
| `DrainReachability.cfg` | expected failure | 5,222 | 1,998 | 17 |
| `TwoSceneReachability.cfg` | expected failure | 4 | 3 | 3 |
| `QuietReachability.cfg` | expected failure | 7 | 5 | 4 |
| `CalibrationReachability.cfg` | expected failure | 25 | 16 | 6 |
| `ContextGateReachability.cfg` | expected failure | 7 | 5 | 4 |
| `ContextRenewalReachability.cfg` | expected failure | 65 | 46 | 8 |
| `GatedSuccessorSyncReachability.cfg` | expected failure | 151 | 98 | 10 |
| `OldActivationAfterSuccessorReachability.cfg` | expected failure | 308 | 187 | 12 |
| `OldActivationWhileGatedReachability.cfg` | expected failure | 217 | 136 | 11 |
| `DelayedRuntimeTeardownReachability.cfg` | expected failure | 1,340 | 694 | 20 |
| `ContextPollerReachability.cfg` | expected failure | 1,220 | 633 | 19 |
| `PhysicalSuspensionReachability.cfg` | expected failure | 824 | 360 | 16 |
| `SameLeaseResumeReachability.cfg` | expected failure | 1,618 | 677 | 26 |
| `DemandOvertakeReachability.cfg` | expected failure | 551 | 252 | 14 |

The check used tla2tools 1.7.4, TLC2 2.19 at revision `5a47802`, and
PlusCal 1.11. It used Temurin Java 21.0.8+9. The pinned `tla2tools.jar`
SHA-256 is `936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88`.

Deterministic Swift guards:

- [`ProjectionExperienceCoordinatorTests.exactActiveRenewalRetiresAndRemintsInOneCoordinatorTurn`](../../ThrowUI/Tests/ProjectionExperienceCoordinatorTests.swift)
- [`ProjectionExperienceCoordinatorTests.renewingTransitionTargetRetiresItAndRejectsOldCallbacks`](../../ThrowUI/Tests/ProjectionExperienceCoordinatorTests.swift)
- [`ProjectionExperienceCoordinatorTests.renewingPrewarmRetiresItAndRejectsOldCallbacks`](../../ThrowUI/Tests/ProjectionExperienceCoordinatorTests.swift)
- [`ProjectionExperienceCoordinatorTests.renewingCommittedTargetRemintsItAndInvalidatesOldCompletion`](../../ThrowUI/Tests/ProjectionExperienceCoordinatorTests.swift)
- [`ThrowSessionAircraftTests.samePermitSourceReconfigurationRenewsLeaseAndPhysicalPoller`](../../ThrowUI/Tests/ThrowSession+AircraftTests.swift)
- [`ThrowSessionExperiencesTests.staleDeactivationCannotReleaseANewerSessionLease`](../../ThrowUI/Tests/ThrowSession+ExperiencesTests.swift)
- [`AirAndSpaceRuntimeTests.suspendedPollingRejectsAnOldPublicationAndResumesTheSameLease`](../../ThrowUI/Tests/AirAndSpaceRuntimeTests.swift)
- [`AirAndSpaceRuntimeTests.newerDeactivationTombstonesActivationSuspendedDuringReset`](../../ThrowUI/Tests/AirAndSpaceRuntimeTests.swift)
- [`ThrowSessionTests.geographyKeepsItsLeaseWhilePhysicalPollingStopsAndResumes`](../../ThrowUI/Tests/ThrowSessionTests.swift)
- [`ThrowSessionTests.disablingEveryLayerSuspendsWithoutRetiringTheCoordinatorLease`](../../ThrowUI/Tests/ThrowSessionTests.swift)
- [`ThrowSessionTests.nonOperationalLaunchSuspendsWithoutRetiringTheCoordinatorLease`](../../ThrowUI/Tests/ThrowSessionTests.swift)
- [`ThrowSessionTests.stoppedDemandRejectsADelayedOlderActivationUnderTheSameLease`](../../ThrowUI/Tests/ThrowSessionTests.swift)
- [`ThrowRuntimeTests.twoControllerScenesOwnAggregateForegroundPresence`](../../Throw/Tests/ThrowRuntimeTests.swift)
- [`AircraftPollingCoordinatorTests.replacementCancelsAndDrainsBeforeStartingTheNewSource`](../../ThrowCore/Tests/AircraftPollingCoordinatorTests.swift)

This result is not an implementation proof. A change to demand scheduling,
context invalidation, lease renewal, direct synchronization, actor admission,
runtime tombstones, physical demand generations, or Core replacement invalidates
it.
