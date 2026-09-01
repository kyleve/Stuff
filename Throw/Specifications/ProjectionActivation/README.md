# Projection activation

This model checks one question:

> Does Throw stop physical aircraft polling after projection loses permission, without letting an old teardown stop a newer activation?

The model represents the activation protocol at production commit
`69fc5f27647199d6d6a5f4733b37a9707f64e286`. Commit `f035acc1` hid stopped
coordinator leases. Commit `69fc5f27` added the runtime generation tombstone.

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
| `requestRevision` and `CaptureLatest` | [`scheduleDemandReconciliation()` and `reconcileDemand(generation:)`](../../ThrowUI/Sources/Model/ThrowSession+Aircraft.swift) coalesce demand by `demandGeneration`. |
| `RawPermit` | Raw scene, output, quiet, and calibration inputs supplied by `ThrowSession`. |
| `reconciledPermit` | [`ProjectionExperienceDemand.permitsProjection` and `ProjectionExperienceCoordinator.reconcile(demand:)`](../../ThrowUI/Sources/Model/ProjectionExperienceCoordinator.swift) own accepted coordinator demand. |
| `coordinatorLease` and `issuedLeases` | `activateRuntime(_:role:)` is the only lease issuer in `ProjectionExperienceCoordinator.swift`. |
| `actionQueue` | The coordinator's unbounded action stream and [`applyExperienceCoordinatorAction(_:)`](../../ThrowUI/Sources/Model/ThrowSession+Experiences.swift) form one FIFO action lane. |
| `SynchronizeCurrentLease` | `reconcileExperienceDemand(isQuiet:)` reads `activationLease(for:)` after coordinator reconciliation. The lookup returns only a running runtime lease. |
| `sessionLease` | [`ProjectionActivationLeaseTracker`](../../ThrowUI/Sources/Model/ProjectionExperienceCoordinator.swift) accepts monotonic activation and exact deactivation. |
| `runtimeLease` and `latestRuntimeLease` | [`AirAndSpaceRuntime.ActivationLifecycle`](../../ThrowUI/Sources/Model/AirAndSpaceRuntime.swift) stores active ownership or a monotonic inactive tombstone. |
| `pollQueue` and poll operation phases | [`AircraftPollingCoordinator`](../../ThrowCore/Sources/AircraftPollingCoordinator.swift) serializes lifecycle requests through `lifecycleTail`. |
| `DrainPhysicalPoller` and `StartPhysicalPoller` | `performDeactivate(...)` and `replace(...)` cancel and drain the old task before a current request starts a new task. |

`RawPermit` is requested permission. `reconciledPermit` is the last permission
accepted by the coordinator. Requested permission can change while
reconciliation, action dispatch, runtime teardown, or poller drain is pending.
The model does not collapse this interval.

Each labeled PlusCal action represents one atomic region or one suspension
boundary. Coordinator calls are serialized in one coalescing demand lane.
Events can change raw permission while that lane is suspended. FIFO actions,
runtime commands, and poller lifecycle requests can then interleave.

The model permits a captured request to become stale while it is suspended. It
does not permit a second coordinator call to overtake that request. This is an
explicit assumption about the main-actor scheduler and actor admission order.

## Properties

- `TypeOK` checks every variable domain.
- `OwnershipUsesIssuedLeases` rejects any lease not issued by the coordinator.
- `NoStaleTeardownOfNewerLease` requires a session teardown to match its victim.
- `AtMostOnePhysicalPoller` limits the physical poller set to one lease.
- `PermitSafety` permits a physical poller after raw permission becomes false
  only during current reconciliation or teardown that can retire that poller.
- `CorrectAtQuiescence` requires raw permission, reconciled permission,
  coordinator state, leases, and the physical poller to agree when work stops.
- `EventuallyConverges` requires that agreement after all finite events finish.

Reachability controls prove that TLC visits the following states:

- Raw and reconciled permission differ.
- A physical poller remains while loss-of-permission teardown is pending.
- Direct synchronization reads the coordinator's current lease.
- An old teardown waits behind a newer session lease.
- A newer runtime teardown installs a tombstone.
- Physical poller replacement enters its drain phase.
- A physical poller starts.
- Two controller scenes are foreground together.
- Quiet time and calibration each block permission.

## Bounds, fairness, and exclusions

`LeaseReplacementRace` has one scene, one output, and four events. It cycles
permission off and on to issue two leases.

`SingleSceneEvents` has one scene, one output, and seven events. It exercises
quiet and calibration changes before the scene leaves the foreground.

`TwoSceneEvents` has two scenes, two outputs, and twelve events. It changes each
scene and output independently. The current configurations check all three
event plans.

The finite environment eventually submits every configured event. Each enabled
reconciliation, action, runtime, and poller lane eventually takes a step. These
fairness assumptions support `EventuallyConverges`.

The model assumes that the app is operational and has an enabled layer, valid
location, source, credential, and query. It checks physical poller ownership,
not provider request completion.

The model excludes provider failures, network results, GPS, projection math,
rendering, prewarming, playlist transitions, preference changes, process
termination, and infinite event streams. It also excludes same-lease source or
query replacement because those changes do not change activation ownership.

## Negative controls

`BrokenIdentityTeardown.cfg` models teardown by experience identity. TLC finds
this trace:

1. Permission starts lease 1.
2. Quiet time queues lease 1 deactivation.
3. Permission returns and starts lease 2.
4. The delayed lease 1 command clears session lease 2.
5. `NoStaleTeardownOfNewerLease` fails at depth 18.

`PreFixStoppedLease.cfg` models the coordinator lookup before `f035acc1`.
The deactivation action clears lease 1. Direct synchronization then reads the
stored lease from a stopped runtime and restores it. `CorrectAtQuiescence`
fails at depth 20.

`PreFixRuntimeTombstone.cfg` models the runtime before `69fc5f27`. Lease 1
activation suspends during reset. Lease 2 deactivation arrives first and has no
active lease to clear. Lease 1 then starts a physical poller without raw or
reconciled permission. `PermitSafety` fails at depth 30.

Each control uses the same state and the same current-design property that it
must falsify. The manifest requires the named failure, so another error does
not count as a successful control.

## Result

**Verified for these model bounds and assumptions.** TLC exhausted every
current configuration with no invariant, temporal, or deadlock error.

| Configuration | Result | Generated | Distinct | Depth |
| --- | ---: | ---: | ---: | ---: |
| `CurrentRace.cfg` | pass | 2,744 | 1,204 | 29 |
| `CurrentSingle.cfg` | pass | 470,566 | 158,337 | 52 |
| `CurrentTwoScenes.cfg` | pass | 4,179,924 | 1,196,080 | 65 |
| `BrokenIdentityTeardown.cfg` | expected failure | 878 | 437 | 18 |
| `PreFixStoppedLease.cfg` | expected failure | 6,557 | 2,932 | 20 |
| `PreFixRuntimeTombstone.cfg` | expected failure | 85,881 | 31,298 | 30 |
| `PermitGapReachability.cfg` | expected failure | 5 | 5 | 4 |
| `PermitTeardownReachability.cfg` | expected failure | 335 | 211 | 11 |
| `DirectLeaseSyncReachability.cfg` | expected failure | 24 | 22 | 6 |
| `RaceReachability.cfg` | expected failure | 878 | 437 | 18 |
| `PhysicalReachability.cfg` | expected failure | 222 | 147 | 10 |
| `RuntimeTombstoneReachability.cfg` | expected failure | 647 | 381 | 13 |
| `DrainReachability.cfg` | expected failure | 3,180 | 1,467 | 17 |
| `TwoSceneReachability.cfg` | expected failure | 3 | 3 | 3 |
| `QuietReachability.cfg` | expected failure | 5 | 5 | 4 |
| `CalibrationReachability.cfg` | expected failure | 17 | 16 | 6 |

The check used tla2tools 1.7.4, TLC2 2.19 at revision `5a47802`, and
PlusCal 1.11. It used Temurin Java 21.0.8+9. The pinned `tla2tools.jar`
SHA-256 is `936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88`.

Deterministic Swift guards:

- [`ThrowSessionExperiencesTests.staleDeactivationCannotReleaseANewerSessionLease`](../../ThrowUI/Tests/ThrowSession+ExperiencesTests.swift)
- [`ThrowSessionExperiencesTests.stoppedCoordinatorLeaseCannotReappearAfterItsDeactivationAction`](../../ThrowUI/Tests/ThrowSession+ExperiencesTests.swift)
- [`AirAndSpaceRuntimeTests.staleLeaseQueuedBeforeReplacementCannotDeactivateTheReplacement`](../../ThrowUI/Tests/AirAndSpaceRuntimeTests.swift)
- [`AirAndSpaceRuntimeTests.newerDeactivationTombstonesActivationSuspendedDuringReset`](../../ThrowUI/Tests/AirAndSpaceRuntimeTests.swift)
- [`ProjectionExperienceCoordinatorTests.backgroundQuietAndCalibrationStopEveryRuntimeAndTimer`](../../ThrowUI/Tests/ProjectionExperienceCoordinatorTests.swift)
- [`ThrowRuntimeTests.twoControllerScenesOwnAggregateForegroundPresence`](../../Throw/Tests/ThrowRuntimeTests.swift)
- [`AircraftPollingCoordinatorTests.replacementCancelsAndDrainsBeforeStartingTheNewSource`](../../ThrowCore/Tests/AircraftPollingCoordinatorTests.swift)

This result is not an implementation proof. A change to demand scheduling,
coordinator admission, lease issuance, action ordering, teardown, runtime
tombstones, or poller replacement invalidates it.
