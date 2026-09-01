# Preference transactions

This model checks one narrow question. Can a source or observer mutation cross storage and render
awaits without publishing an uncommitted setup or reviving an obsolete observer context?

The model represents Throw at revision `69fc5f27647199d6d6a5f4733b37a9707f64e286`. The modeled
revision includes the transaction fixes in `fd79ac53`, `79d685a1`, `98521ce5`, `8fd8e5af`,
`e1a03232`, and `2862590b`. A relevant change to these paths invalidates this result until the
mapping is checked again.

## Source correspondence

| Model state or action | Production counterpart |
| --- | --- |
| `livePreferences` | `ThrowSession.preferenceSnapshot`, including the authoritative live setup |
| `durablePreferences` | The last successful `ThrowPreferenceStore.save(_:)` value |
| `credentials` | Credential IDs present in `AircraftCredentialStore` |
| `candidateBase` | The snapshot captured at `persistReconciledPreferenceMutation` line 209 |
| `candidatePreferences` | `PersistableThrowPreferenceMutation.preferences` |
| `commitKnown` / `committedCandidate` | `ThrowPreferenceMutationCommitState.committed` |
| `foregroundEditQueued` | A typed UI edit deferred by `schedulePreferencesSave` during a mutation |
| `queuedForegroundSnapshot` | The complete live snapshot enqueued by `finishPreferenceMutation` |
| `requestKind` / `workerPhase` | `ThrowPreferencePersistenceState` and `drainPreferenceSaveQueue()` |
| Credential read, save, and restore phases | The three credential-store awaits in `useSource(_:)` |
| `publicationState` | Whether the complete mutation snapshot and its side state became live |
| `invalidationActive` | `projectionPreferenceInvalidation` from preparation through completion |
| `contextGeneration` | `ThrowSession.projectionContextGeneration` |
| `publishedObserverGeneration` | The observer identity in the published setup generation |
| Activation fields | The active or prepared projection lease and its observer context |
| Render fields | The context captured before `projectedOutput` suspends |
| Visible-frame fields | The observer context carried by the visible projection |

The source mutation waits for the existing worker. It then awaits credential read and credential
save before it can enqueue preferences. A failed uncommitted source save awaits credential restore.
The model splits all these awaits.

The serialized preference worker has separate dequeue and store-completion steps. Each store
completion can succeed or fail. A successful write updates durable preferences before the caller
learns the result. A foreground edit can run only while the main-actor mutation is suspended.

Publication is one atomic main-actor step. It records commit knowledge, invalidates the projection
context, and publishes the complete candidate. An observer publication also clears the visible
frame. Later steps model runtime deactivation, projection-worker reset, coordinator configuration,
coordinator state read, source-frame fade, and the final worker reset.

The renderer captures the active context before its worker await. It publishes only if the context,
activation, observer, and invalidation state still match. Otherwise, it records a stale rejection.

## Properties

- `TypeOK` checks every model variable.
- `ReportedFailureKeepsDurableSetup` checks that a reported failure did not commit a new source or
  observer behind the live setup.
- `PersistedSourceHasAlignedCredential` checks that each persisted credential-backed source has its
  required credential ID.
- `VisibleFrameMatchesPublishedObserver` checks the observer identity and generation of each visible
  frame.
- `ActiveProjectionMatchesPublishedObserver` checks the active projection context.
- `PublicationFollowsDurableCommit` prevents setup publication before a successful preference write.
- `EventuallyReports` requires the finite mutation to return success or failure.
- `EventuallyQuiescent` requires the transaction and its deferred save to finish.

Weak fairness applies only to the modeled mutation, storage worker, activation, renderer, and finite
foreground editor. It means that an enabled await completion eventually runs. The safety invariants
do not depend on fairness.

## Bounds and exclusions

The initial source and observer use generation zero. The target source uses one credential ID. The
target observer uses generation one. TLC checks both mutation kinds and every success or failure of
candidate construction and storage.

| Configuration | Foreground edits | Mutation kinds | Generated / distinct states | Depth |
| --- | ---: | --- | ---: | ---: |
| `CurrentSmall.cfg` | 1 | source and location | 2,677 / 972 | 32 |
| `CurrentExpanded.cfg` | 2 | source and location | 9,258 / 3,261 | 37 |

The model includes one preference mutation and one coalesced foreground save. It does not model an
unbounded edit stream, process termination, direct credential deletion, malformed persisted data,
location acquisition, source polling, or experience rotation. Credential alignment means that the
required credential ID is present. Secret contents and failed rollback diagnostics are outside the
claim.

## Controls and result

`BrokenRetry.cfg` removes committed-candidate knowledge. Its trace writes the new source, observes a
foreground edit, fails the retry, restores the credential, and reports failure against the old live
source. Credential restore first violates `PersistedSourceHasAlignedCredential`. The next caller
step would also report a durable and live setup mismatch. This is the success, drift, retry-failure
bug fixed by `98521ce5`.

`BrokenObserver.cfg` publishes the new observer before the preference save. The old active context
and visible frame remain published. This is the observer transaction bug fixed by `fd79ac53`.

`CurrentRetryReachability.cfg` proves that the current model reaches a committed retry failure and
queues its foreground reconciliation. `CurrentStaleRenderReachability.cfg` proves that a render from
the old observer can complete after publication and is rejected.

**Verified for these model bounds and assumptions.** Both current configurations completed without
an invariant, temporal-property, or deadlock error. The retry control failed after 178 generated and
97 distinct states at depth 17. The observer control failed after five states at depth three.

The retry reachability control failed after 789 generated and 364 distinct states at depth 23. The
stale-render reachability control failed after 75 generated and 35 distinct states at depth nine.
These expected failures confirm that TLC reached each important branch.

## Run it

From the repository root:

```sh
./tla-check PreferenceTransactions
```
