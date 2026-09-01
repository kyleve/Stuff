# Preference transactions

This model checks one question:

> Can a source or observer mutation preserve durable state, renew its exact lease, and reject delayed work from the replaced context?

The model represents the protocol at production commit
`eec278ee956f631f442db46b49e5c534499a3e66`. A relevant source change
invalidates this result until the mapping is checked again.

The tracked source contains only PlusCal. `./tla-check` translates it in the
retained run directory. Do not run `pcal.trans` directly.

Run the model from the repository root:

```sh
./tla-check PreferenceTransactions
```

## Source correspondence

| Model state or action | Production authority |
| --- | --- |
| `livePreferences` | [`ThrowSession.preferenceSnapshot`](../../ThrowUI/Sources/Model/ThrowSession+Preferences.swift) is the complete live setup. |
| `durablePreferences` | `ThrowPreferenceStore.save(_:)` owns the last successful stored setup. |
| `credentials` | [`AircraftCredentialStore`](../../ThrowUI/Sources/Model/ThrowSession+Aircraft.swift) owns stored credential identities. |
| `candidateBase` | `persistReconciledPreferenceMutation` captures `preferenceSnapshot` at line 221. |
| `candidatePreferences` | `PersistableThrowPreferenceMutation.preferences` is the validated storage value. |
| `commitKnown` and `committedCandidate` | `ThrowPreferenceMutationCommitState.committed` records a successful durable write. |
| `foregroundEditQueued` | `schedulePreferencesSave` defers a typed edit while the mutation producer owns persistence. |
| `queuedForegroundSnapshot` | `finishPreferenceMutation` queues the complete live snapshot after the producer finishes. |
| `requestKind` and `workerPhase` | `ThrowPreferencePersistenceState` and `drainPreferenceSaveQueue()` serialize preference writes. |
| Credential read, save, and restore phases | [`useSource(_:)` lines 166-258](../../ThrowUI/Sources/Model/ThrowSession+Aircraft.swift) contain the three credential-store suspension boundaries. |
| `publicationState` | [`persistReconciledPreferenceMutation` lines 278-285](../../ThrowUI/Sources/Model/ThrowSession+Preferences.swift) publishes only after a successful write. |
| `invalidationActive` and `contextGeneration` | [`prepareProjectionPreferencePublication` lines 484-510](../../ThrowUI/Sources/Model/ThrowSession+Aircraft.swift) opens the gate and replaces the context generation. |
| `capturedLease` | The invalidation captures `airAndSpaceActivation.activeLease` before it tombstones the session tracker. |
| `renewalResult` and `coordinatorLease` | [`renewActivationLease` lines 415-452](../../ThrowUI/Sources/Model/ProjectionExperienceCoordinator.swift) returns `replaced`, `retired`, or `superseded`. |
| `sessionLease` and `latestSessionLease` | [`ProjectionActivationLeaseTracker` lines 71-131](../../ThrowUI/Sources/Model/ProjectionExperienceCoordinator.swift) stores active ownership or an inactive generation tombstone. |
| `runtimeLease` and `latestRuntimeLease` | [`AirAndSpaceRuntime.ActivationLifecycle` lines 202-243](../../ThrowUI/Sources/Model/AirAndSpaceRuntime.swift) stores runtime ownership or a generation tombstone. |
| `directRetirementLease` | [`finishProjectionPreferenceInvalidation` lines 513-547](../../ThrowUI/Sources/Model/ThrowSession+Aircraft.swift) passes the captured lease to direct runtime deactivation. |
| `actionQueue` | The coordinator action stream and [`applyExperienceCoordinatorAction(_:)` lines 152-197](../../ThrowUI/Sources/Model/ThrowSession+Experiences.swift) form one FIFO callback lane. |
| `callbackPhase` and `callbackLease` | A deactivation can suspend during `projectionWorker.experienceBecameInactive` and `airAndSpaceRuntime.deactivate`. |
| Coordinator configuration, state, and lease phases | [`configureExperienceCoordinator` lines 232-240](../../ThrowUI/Sources/Model/ThrowSession+Experiences.swift) performs these operations in that order. |
| Source cleanup phases | [`discardOldFrame` lines 1065-1097](../../ThrowUI/Sources/Model/ThrowSession+Aircraft.swift) fades the old frame before the worker reset. |
| Observer cleanup phase | `finishProjectionPreferenceInvalidation` resets the projection worker for an observer mutation. |
| Activation fields | The active or prepared projection context carries its exact coordinator, session, and runtime lease. |
| Render fields | The renderer captures its context and observer before the worker suspension. |
| Visible-frame fields | A visible projection carries the observer and context generation that produced it. |

The source mutation first waits for the existing preference worker. It then
reads and saves a credential before it queues the candidate preferences.
A failed uncommitted source write restores the previous credential.

The preference worker separates dequeue from store completion. Each store
completion can succeed or fail. A successful completion changes durable state
before the mutation learns the result.

A foreground edit can run while the main-actor mutation is suspended. The
mutation retries against the latest complete snapshot after it detects drift.
If an earlier attempt committed, later failure publishes a committed candidate
and queues reconciliation.

Publication is one atomic main-actor step. It prepares invalidation, publishes
the complete snapshot, publishes the mutation payload, and records commit
resolution.

The source path then performs these operations:

1. Renew the captured coordinator lease.
2. Retire the exact captured runtime lease.
3. Fade and discard the old frame.
4. Reset the projection worker.
5. Configure the coordinator.
6. Read and apply coordinator state.
7. Read and synchronize the authoritative lease.
8. Complete the invalidation gate.

The observer path clears its visible frame during publication. It then performs
lease renewal, runtime retirement, and projection-worker reset. The final
configuration, state, lease, and gate order matches the source path.

The direct coordinator lease read can overtake queued action callbacks. The
model therefore permits old callbacks before or after direct successor
synchronization. It also permits a callback to suspend across that
synchronization.

The gate rejects delayed activation during invalidation. The session and
runtime generation tombstones reject obsolete work after invalidation. A
delayed old runtime teardown cannot retire successor lease 2.

## Properties

- `TypeOK` checks every variable domain.
- `LeaseLifecycleShape` checks active leases and inactive tombstones.
- `RenewalResultMatchesAuthority` checks each renewal result against the
  coordinator lease.
- `CapturedLeaseRetirementIsExact` requires direct runtime retirement to target
  captured lease 1 only.
- `InvalidationCompletionFollowsRequiredWork` requires renewal, retirement,
  cleanup, configuration, state read, and lease synchronization before gate
  completion.
- `OldCallbacksPreserveSuccessor` keeps successor session and runtime lease 2
  after delayed lease 1 callbacks.
- `ReportedFailureKeepsDurableSetup` prevents a reported failure from hiding a
  committed source or observer change.
- `PersistedSourceHasAlignedCredential` requires each stored credential-backed
  source to have its credential identity.
- `VisibleFrameMatchesPublishedObserver` checks each visible frame against the
  published observer and generation.
- `ActiveProjectionMatchesPublishedObserver` checks context, observer, and all
  three lease owners for an active projection.
- `PublicationFollowsDurableCommit` prevents setup publication before a
  successful preference write.
- `EventuallyReports` requires the finite mutation to return success or
  failure.
- `EventuallyQuiescent` requires the transaction and its deferred save to
  finish.

Reachability controls prove that TLC visits these states:

- A committed retry failure queues foreground reconciliation.
- An old render finishes after observer publication and is rejected.
- Invalidation completes after every required phase.
- Renewal returns `replaced`, `retired`, and `superseded`.
- Old activation and deactivation callbacks run after direct successor sync.
- An accepted old deactivation suspends while successor runtime lease 2 starts.

## Bounds, fairness, and exclusions

The initial source and observer use value zero. The target source and observer
use value one. The target source uses one credential identity.

Lease 0 means no active lease. Lease 1 is the captured lease. Lease 2 is the
only successor lease. The model contains one runnable experience.

The model includes one preference mutation and one coalesced foreground save.
`CurrentSmall.cfg` allows one foreground edit. `CurrentExpanded.cfg` allows two
foreground edits. Both configurations check source and observer mutations.

The bounded model queues one old activation callback when publication starts.
A renewal then queues its source-faithful sequence:

- `replaced` queues old deactivation and successor activation.
- `retired` queues old deactivation and leaves no authoritative lease.
- `superseded` leaves successor lease 2 authoritative and queues its pending
  activation.

The bounded `retired` branch includes a pending old deactivation. The model
excludes retirement without a pending callback.

The FIFO callback lane can hold all three bounded commands. It completes one
accepted deactivation before it dispatches the next command. The direct lease
read is outside that callback lane.

Weak fairness applies to the finite mutation, persistence worker, callback
lane, activation, renderer, and foreground editor. These assumptions support
the two temporal properties. The safety properties do not depend on fairness.

The model excludes unbounded edits, process termination, direct credential
deletion, malformed stored data, location acquisition, provider results, and
projection math. It also excludes physical poller and demand lifecycles.

[`ProjectionActivation`](../ProjectionActivation/README.md) owns the full
coordinator, session, runtime, demand, and physical-poller protocol. Its
`PreFixContextRetainedLease.cfg` control falsifies `FreshContextAtQuiescence`
when context replacement retains the same lease.

That model also proves gated and delayed callback reachability. Its relevant
probes include `OldActivationWhileGatedAfterSuccessorNotReached`,
`OldActivationAfterSuccessorNotReached`, and
`DelayedRuntimeTeardownAfterSuccessorNotReached`.

This model checks how one stored mutation crosses that lease protocol. It does
not duplicate the full lifecycle proof.

## Negative controls

`BrokenRetry.cfg` removes committed-candidate knowledge. TLC finds this trace:

1. The first candidate write commits the new source.
2. A foreground edit changes the live snapshot.
3. The retry fails.
4. The mutation restores the credential and reports failure.
5. `PersistedSourceHasAlignedCredential` fails at depth 17.

This trace represents the success, drift, and retry-failure bug fixed by
`98521ce5`.

`BrokenObserver.cfg` publishes the observer before its preference write. The
old visible frame remains published. `VisibleFrameMatchesPublishedObserver`
fails at depth three.

This trace represents the observer transaction bug fixed by `fd79ac53`.

`BrokenInvalidation.cfg` skips the authoritative lease read and session sync.
It still performs renewal, exact runtime retirement, cleanup, configuration,
and state read. It then completes the gate.

`InvalidationCompletionFollowsRequiredWork` fails at depth 18. This control is
a narrow transaction mutation. It does not replace the historical same-lease
control in `ProjectionActivation`.

Each negative control uses the current state and a current-design property.
The manifest requires the named failure. Another error does not count as a
successful control.

## Result

**Verified for these model bounds and assumptions.** TLC exhausted both
current configurations without an invariant, temporal, or deadlock error.

| Configuration | Result | Generated | Distinct | Depth |
| --- | ---: | ---: | ---: | ---: |
| `CurrentSmall.cfg` | pass | 47,249 | 13,971 | 39 |
| `CurrentExpanded.cfg` | pass | 181,368 | 52,032 | 44 |
| `BrokenRetry.cfg` | expected failure | 576 | 302 | 17 |
| `BrokenObserver.cfg` | expected failure | 5 | 5 | 3 |
| `BrokenInvalidation.cfg` | expected failure | 353 | 184 | 18 |
| `CurrentRetryReachability.cfg` | expected failure | 5,923 | 2,762 | 25 |
| `CurrentStaleRenderReachability.cfg` | expected failure | 89 | 46 | 9 |
| `CurrentInvalidationReachability.cfg` | expected failure | 436 | 225 | 19 |
| `CurrentRenewalReplacedReachability.cfg` | expected failure | 97 | 43 | 12 |
| `CurrentRenewalRetiredReachability.cfg` | expected failure | 98 | 44 | 12 |
| `CurrentRenewalSupersededReachability.cfg` | expected failure | 99 | 45 | 12 |
| `CurrentOldCallbackReachability.cfg` | expected failure | 527 | 271 | 20 |
| `CurrentDelayedRuntimeTeardownReachability.cfg` | expected failure | 1,410 | 593 | 26 |

The old-callback trace performs direct successor sync before it dispatches old
activation and deactivation callbacks. Both callbacks preserve session lease
2.

The delayed-teardown trace accepts old deactivation while the session tracker
contains the lease 1 tombstone. Its runtime await crosses direct sync and
successor activation. Runtime lease 2 remains active.

The check used tla2tools 1.7.4, TLC2 2.19 at revision `5a47802`, and PlusCal
1.11. It used Temurin Java 21.0.8+9. The pinned `tla2tools.jar` SHA-256 is
`936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88`.

Deterministic Swift guards:

- [`ThrowSessionAircraftTests.sourceInvalidationRejectsAPendingRenderAndRepeatedLease`](../../ThrowUI/Tests/ThrowSession+AircraftTests.swift)
- [`ThrowSessionAircraftTests.samePermitSourceReconfigurationRenewsLeaseAndPhysicalPoller`](../../ThrowUI/Tests/ThrowSession+AircraftTests.swift)
- [`ProjectionExperienceCoordinatorTests.exactActiveRenewalRetiresAndRemintsInOneCoordinatorTurn`](../../ThrowUI/Tests/ProjectionExperienceCoordinatorTests.swift)
- [`ProjectionExperienceCoordinatorTests.renewingTransitionTargetRetiresItAndRejectsOldCallbacks`](../../ThrowUI/Tests/ProjectionExperienceCoordinatorTests.swift)
- [`ProjectionExperienceCoordinatorTests.renewingPrewarmRetiresItAndRejectsOldCallbacks`](../../ThrowUI/Tests/ProjectionExperienceCoordinatorTests.swift)
- [`ThrowSessionExperiencesTests.staleDeactivationCannotReleaseANewerSessionLease`](../../ThrowUI/Tests/ThrowSession+ExperiencesTests.swift)
- [`ThrowSessionExperiencesTests.delayedEqualDeactivationStillStopsRuntimeAfterDirectNilSync`](../../ThrowUI/Tests/ThrowSession+ExperiencesTests.swift)
- [`AirAndSpaceRuntimeTests.staleLeaseQueuedBeforeReplacementCannotDeactivateTheReplacement`](../../ThrowUI/Tests/AirAndSpaceRuntimeTests.swift)
- [`AirAndSpaceRuntimeTests.newerDeactivationTombstonesActivationSuspendedDuringReset`](../../ThrowUI/Tests/AirAndSpaceRuntimeTests.swift)

This result is not an implementation proof. Changes to preference storage,
publication, invalidation order, lease renewal, action ordering, session
tombstones, runtime tombstones, activation, or rendering invalidate it.
