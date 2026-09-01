# Projection context transition

This model checks one question:

> Can Throw publish a prepared projection after its source, observer, lease, or semantic revision becomes obsolete?

The model represents the projection-context code at production commit
`69fc5f27`. Commit `2862590b` introduced the checked invalidation protocol.

The model uses raw TLA+. Each named action represents one suspension boundary.
This declarative form keeps environment invalidation independent from worker,
coordinator, and animation completion.

Run the model from the repository root:

```sh
./tla-check ProjectionContextTransition
```

## Source correspondence

| Model state or action | Production authority |
| --- | --- |
| `context` | `ThrowSession.projectionContextGeneration` in `ThrowSession.swift` |
| `inputRevision` | `ThrowSession.projectionInputRevision` and the pending semantic frame |
| `coordinatorLease` | `ProjectionActivationLease` issued by `ProjectionExperienceCoordinator` |
| `stagePhase` and staged fields | `ProjectionPresentationStaging` and `PreparedProjectionPresentation` |
| visible fields | the closed `ProjectionPresentationState` and `VisibleProjection` |
| `StartPreparation` and `CompleteWorker` | `applyAirAndSpaceUpdate(_:)` before and after `projectedOutput(...)` |
| prepared report actions | the await of `reportRuntimePrepared(_:)` and its post-await checks |
| fade actions | `transitionExperience(from:to:)` before and after each fade await |
| coordinator commit actions | the await of `commitTransitionState(to:)` |
| `CommitCurrentPreparedPair` | `commitPreparedProjectionAtBlack(coordinator:)` |
| `UpdateTargetInput` | a newer runtime update buffered by `ProjectionPresentationStaging` |
| `InvalidateProjectionContext` | `prepareProjectionPreferencePublication(_:)` |
| `FinishInvalidation` | runtime teardown, coordinator synchronization, old-frame removal, and invalidation completion |
| `CompleteFadeIn` | `finishProjectionPresentationTransition(to:)` |

The source splits at every modeled await. The model does not treat task
cancellation as immediate completion.

## Properties

- `TypeOK` checks every variable domain.
- `StagingShape` checks the closed staging lifecycle.
- `OperationalVisibleIdentity` binds an operational visible frame to the
  current context and coordinator lease.
- `ExactVisiblePair` requires matching semantic and projected revisions.
- `NoInvalidatedContextCommit` rejects a black commit from an invalid context.
- `NoMismatchedCommit` rejects the old mixed-revision commit design.
- `NoWriterDuringFadeIn` keeps runtime writers out of the fade-in phase.
- `RequiredPathsNotAllReached` is an anti-vacuity probe. TLC must falsify it.

The reachability case visits preparation, a black commit, a buffered revision,
and invalidation during preparation and fade.

## Bounds and assumptions

`CurrentSmall.cfg` explores one context change, one later input revision, and
two activation leases. `CurrentLarger.cfg` explores two context changes, two
later revisions, and three leases.

The model makes these assumptions:

- One target projection can be staged at a time.
- Source and observer changes use the same context-generation protocol.
- The coordinator returns a lease identity, not an untyped experience ID.
- An invalidation gate can temporarily retain an old visible source frame.
- The gate must remove that frame before normal operation resumes.

The model checks safety only. It does not assume that timers, providers, or
animation callbacks must eventually return.

The model excludes projection math, pixels, route enrichment, polling, playlist
selection policy, preference persistence, and application scene admission.

## Negative controls

`BrokenContext.cfg` keeps staged work during invalidation and omits the final
context check. TLC finds this nine-state trace:

1. The worker prepares context 0 and lease 1.
2. The presentation fades out and starts the coordinator commit await.
3. An invalidation advances the current context to 1.
4. The old prepared frame commits at black.
5. `NoInvalidatedContextCommit` fails.

`BrokenPair.cfg` reproduces the prior mixed-frame shortcut. A later semantic
revision arrives while the coordinator commit suspends. The black exchange then
combines semantic revision 1 with projected revision 0. `ExactVisiblePair`
fails after nine states.

`BrokenWriter.cfg` publishes a buffered update during fade-in. TLC reaches the
write after ten states, and `NoWriterDuringFadeIn` fails.

These controls use the same variables and safety properties as the current
design.

## Result

**Verified for these model bounds and assumptions.** TLC exhausted both current
configurations with no error.

| Configuration | Result | Generated | Distinct | Depth |
| --- | ---: | ---: | ---: | ---: |
| `CurrentSmall.cfg` | pass | 683 | 484 | 28 |
| `CurrentLarger.cfg` | pass | 4,422 | 2,341 | 31 |
| `BrokenContext.cfg` | expected failure | 111 | 75 | 9 |
| `BrokenPair.cfg` | expected failure | 89 | 62 | 9 |
| `BrokenWriter.cfg` | expected failure | 109 | 78 | 10 |
| `Reachability.cfg` | expected failure | 351 | 233 | 13 |

The check used tla2tools 1.7.4 (TLC2 2.19, revision `5a47802`) and Temurin Java
21.0.8+9. The pinned `tla2tools.jar` SHA-256 is
`936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88`.

Deterministic Swift guards:

- `ThrowSessionExperiencesTests.blackCommitKeepsPreparedIdentityAndRevisionAheadOfBufferedInput`
- `ThrowSessionExperiencesTests.contextInvalidationWhileRuntimePreparationSuspendsRejectsThePreparedOutput`
- `ThrowSessionExperiencesTests.contextInvalidationDuringFadeRevokesTheBlackCommit`

Any change to the staging lifecycle, context generation, worker publication,
coordinator commit, or fade boundaries invalidates this result.
