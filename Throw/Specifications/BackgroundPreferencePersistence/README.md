# Background preference persistence

This model checks one question. Can Throw reach preference quiescence and release its retained
UIKit background lease safely during producer, worker, scene, cancellation, and expiration races?

The model represents Throw at revision `60c2540189c899a9efca542c157d6b0686710d06`.
It retains controls for the producer-admission fix in `58e15c31f78ee8c842246c72e96d987682edb0cf`.
It also retains the cancellable-waiter control from `27ff3f0c0eb4eece71a371d435f26367f4a06b3d`.

The source map includes context renewal from `b53e5786a0cb97f0a370d22b23ea88f4b4633a83`.
It also includes physical polling suspension from `30b569d9927da66badd92a14663efd604d7b3773`.
Those changes add awaits inside producer scopes but do not change the persistence protocol.

The tracked model uses raw TLA+ because it composes parameterized actions without a process scheduler.
The manifest declares `source: tla`.
The checker does not run PlusCal translation for this concern.

A relevant change to the mapped source invalidates this result. Check the map and rerun TLC after
such a change.

## Source correspondence

| Model state or action | Production counterpart |
| --- | --- |
| `foregroundScenes` and the three controller actions | [`ThrowRuntime.controllerScene`](../../Throw/Sources/ThrowRuntime.swift#L190-L209) keeps aggregate foreground membership. Only the first entry and final exit change session state. |
| `admission` and `barrierState.allowed` | [`controllerForegroundPresenceDidChange`](../../ThrowUI/Sources/Model/ThrowSession.swift#L850-L860) calls [`setAcceptsProducers`](../../ThrowUI/Sources/Model/ThrowSession+Preferences.swift#L629-L637) before the runtime starts a flush. Closing admission preserves the active producer set. |
| Typed producer identities and kinds | [`ThrowPreferenceProducerLease`](../../ThrowUI/Sources/Model/ThrowSession+Preferences.swift#L498-L519) and [`ProducerAdmission`](../../ThrowUI/Sources/Model/ThrowSession+Preferences.swift#L550-L566) make admission and exact-once removal explicit. |
| `BeginProducer` and producer completion | [`beginProducer`](../../ThrowUI/Sources/Model/ThrowSession+Preferences.swift#L640-L654), [`finishProducer`](../../ThrowUI/Sources/Model/ThrowSession+Preferences.swift#L656-L670), and the typed mutation wrappers at lines 182-202. |
| Direct selection producers | [`performExperienceSelection`](../../ThrowUI/Sources/Model/ThrowSession+Experiences.swift#L98-L118) covers explicit, next, and previous commands. The producer spans both coordinator awaits and selection publication. |
| Coordinator transition producers | The action-stream task at [`ThrowSession.swift` lines 807-814](../../ThrowUI/Sources/Model/ThrowSession.swift#L807-L814) calls [`applyExperienceCoordinatorAction`](../../ThrowUI/Sources/Model/ThrowSession+Experiences.swift#L152-L210). A denied transition awaits coordinator invalidation instead of publishing. |
| Transition publication and later awaits | [`transitionExperience`](../../ThrowUI/Sources/Model/ThrowSession+Experiences.swift#L295-L420) carries one producer through fade and coordinator awaits. Its publication helpers require that producer at lines 423-457 and 515-524. |
| Mutation producers | [`beginMutation` and `finishMutation`](../../ThrowUI/Sources/Model/ThrowSession+Preferences.swift#L672-L708) combine one mutation with its producer identity. Aircraft, location, and onboarding mutations use this seam. |
| `suspendedAfterPublish` and `PostPublicationAwaitReturns` | Source and observer transactions await renewal and coordinator configuration at [`ThrowSession+Aircraft.swift` lines 260-270](../../ThrowUI/Sources/Model/ThrowSession+Aircraft.swift#L260-L270) and [`ThrowSession+Location.swift` lines 417-420](../../ThrowUI/Sources/Model/ThrowSession+Location.swift#L417-L420). Their admitted mutation remains active. |
| Admitted producer stutter before finish | Active credential deletion awaits physical polling suspension at [`ThrowSession+Aircraft.swift` lines 290-330](../../ThrowUI/Sources/Model/ThrowSession+Aircraft.swift#L290-L330). It releases the mutation producer only after those awaits return. |
| `persistenceState.activity` | The exhaustive [`Activity`](../../ThrowUI/Sources/Model/ThrowSession+Preferences.swift#L536-L548) enum represents idle, saving, mutating, and mutating while saving. |
| Deferred work | [`recordDeferredFailure`](../../ThrowUI/Sources/Model/ThrowSession+Preferences.swift#L710-L742) records save causes during a mutation. [`finishPreferenceMutation`](../../ThrowUI/Sources/Model/ThrowSession+Preferences.swift#L186-L192) schedules them before it removes the producer. |
| Pending, scheduled, and saving requests | [`enqueue`](../../ThrowUI/Sources/Model/ThrowSession+Preferences.swift#L744-L766), [`takeNextRequest`](../../ThrowUI/Sources/Model/ThrowSession+Preferences.swift#L797-L814), and [`drainPreferenceSaveQueue`](../../ThrowUI/Sources/Model/ThrowSession+Preferences.swift#L352-L370). |
| Immediate write and retry phases | [`persistReconciledPreferenceMutation`](../../ThrowUI/Sources/Model/ThrowSession+Preferences.swift#L212-L287) can retry after its storage await. The mutation producer stays active through publication. |
| Typed waiter identities | [`ThrowPreferenceQuiescenceWaiterID`](../../ThrowUI/Sources/Model/ThrowSession+Preferences.swift#L521-L531) gives each continuation a unique identity. |
| Waiter registration, removal, and resume | [`flushPreferencesSave`](../../ThrowUI/Sources/Model/ThrowSession+Preferences.swift#L159-L180) installs a cancellation handler. Lines 829-867 register, remove, and resume waiters only through typed identities. |
| Runtime generation and retained lease | [`BackgroundPreferenceFlushState`](../../Throw/Sources/ThrowRuntime.swift#L108-L119) stores one generation, UIKit lease, and flush task as one value. |
| Runtime start, completion, and expiration | [`startBackgroundPreferenceFlush`](../../Throw/Sources/ThrowRuntime.swift#L243-L258), [`completeBackgroundPreferenceFlush`](../../Throw/Sources/ThrowRuntime.swift#L265-L273), and [`expireBackgroundPreferenceFlush`](../../Throw/Sources/ThrowRuntime.swift#L275-L284). Both exits compare the captured generation. |
| Idempotent UIKit lease end | [`UIApplicationBackgroundExecutionLease.end`](../../Throw/Sources/ThrowRuntime.swift#L48-L63) clears its identifier before it calls UIKit. |

The source has the following asynchronous producer paths:

- `selectExperience`, `selectNextExperience`, and `selectPreviousExperience` use the direct
  selection producer in `performExperienceSelection`.
- Automatic rotation and prepared transitions enter through the coordinator action stream. The
  `beginTransition` action uses the transition producer before it awaits or publishes.
- [`useSource`](../../ThrowUI/Sources/Model/ThrowSession+Aircraft.swift#L166-L273) uses a mutation
  producer for credential, preference, projection, and coordinator awaits.
- Both credential deletion methods use mutation producers at
  [`ThrowSession+Aircraft.swift` lines 276-334](../../ThrowUI/Sources/Model/ThrowSession+Aircraft.swift#L276-L334).
- [`saveObserverLocation`](../../ThrowUI/Sources/Model/ThrowSession+Location.swift#L279-L349) and
  [`accept`](../../ThrowUI/Sources/Model/ThrowSession+Location.swift#L351-L373) use mutation producers.
  [`commitObserverLocation`](../../ThrowUI/Sources/Model/ThrowSession+Location.swift#L375-L422)
  keeps that producer active through persistence, renewal, and coordinator configuration.
- [`completeOnboarding`](../../ThrowUI/Sources/Model/ThrowSession+Onboarding.swift#L5-L86) uses a
  mutation producer around its final write, retry, publication, and coordinator await.

These are all calls to `beginPreferenceMutation` or `beginPreferenceProducer` in production
sources at the modeled revision.

The model represents each main-actor segment as one atomic action. It splits the following real
await or reentrancy boundaries:

- A producer starts before its first await. It can return, publish preference-backed state, await
  more work, and then release its typed lease.
- Source and observer mutations await projection renewal and coordinator configuration after publication.
  They stutter in this model while the admitted mutation remains in `suspendedAfterPublish`.
- Active credential deletion awaits physical polling suspension before producer release.
  That await stutters while the admitted mutation remains active before its finish action.
- The separate [`ProjectionActivation`](../ProjectionActivation/README.md) model verifies those renewal and suspension protocols.
  This model keeps only producer activity across their awaits.
- An immediate mutation write suspends in `preferenceStore.save`. It can retry against a newer
  snapshot before it publishes.
- Starting the preference worker permits main-actor reentrancy before the worker dequeues a request.
- Each store save can succeed, fail, or receive cancellation. The worker then dequeues the next
  request or becomes idle without another await.
- A coordinator transition callback can wait for main-actor entry. Admission can close before that
  entry. A denied callback then waits for coordinator invalidation.
- The runtime task checks cancellation before flush entry. Waiter allocation, handler installation,
  registration, suspension, resumption, and return are separate actions.
- Foreground entry or UIKit expiration can occur between any enabled actions. Each event cancels
  only the matching runtime generation.

## Properties

- `TypeOK` checks every variable and the exhaustive persistence activity shape.
- `QuiescentFlushSafety` permits successful flush return only after the source is quiescent. No
  active admitted producer can publish more preference work.
- `NoUnadmittedPostBarrierWork` rejects preference work from a callback or producer that was not in
  the closed barrier.
- `NoWorkAfterCompletedFlush` rejects any enqueue after a completed background flush while
  admission remains closed.
- `WaitersResumeAtMostOnce` checks exact-once continuation resumption.
- `CanceledReturnHasNoRegisteredWaiter` checks that a canceled flush cannot return with a parked
  continuation.
- `CanceledWaitersTerminateAndAreRemoved` checks cancellation liveness for tasks and typed waiters.
- `LeaseEndExactlyOnce` checks each retained background lease across completion, expiration, and
  foreground cancellation.
- `FinishedFlushReleasedLease` checks that every finished task has released its retained lease.
- `ForegroundGenerationCannotEndNewerLease` rejects completion or expiration from an older
  generation that changes the newer lease.
- `DeniedCoordinatorRequestsEventuallyReconcile` checks that denied automatic transitions clear
  the coordinator request.
- Both current configurations check deadlock. The terminal stutter represents exhaustion of the
  finite generation bound, not an application deadlock.

## Bounds and results

`CurrentSmall.cfg` models one scene, one producer, three requests, and one flush generation. It
checks mutation, selection, transition, deferred-save, retry, worker, waiter, cancellation, and
completion interleavings.

`CurrentRepeated.cfg` models two scenes and two flush generations without producers. This separate
bound isolates aggregate scene membership, typed waiter allocation, stale expiration, and retained
lease ownership.

**Verified for these model bounds and assumptions.**

TLC exhausted both current state spaces without an invariant, temporal, or deadlock error.
The historical controls failed for their mapped reasons.
Both reachability controls reached their required branches.

| Configuration | Purpose | Generated / distinct states | Depth | Result |
| --- | --- | ---: | ---: | --- |
| `CurrentSmall.cfg` | Current producer and persistence protocol | 373,130 / 95,306 | 30 | Pass |
| `CurrentRepeated.cfg` | Current multi-scene and repeated-generation protocol | 35,689 / 9,375 | 21 | Pass |
| `ReachPersistence.cfg` | Persistence anti-vacuity trace | 27,394 / 9,401 | 14 | Expected reachability failure |
| `ReachLifecycle.cfg` | Lifecycle and registered-waiter anti-vacuity trace | 5,122,617 / 1,289,319 | 18 | Expected reachability failure |
| `BrokenUntrackedQuiescence.cfg` | Pre-`58e15c31` callback control | 6,689 / 2,826 | 9 | Expected safety failure |
| `BrokenUntrackedPostBarrier.cfg` | Pre-`58e15c31` post-flush control | 13,754 / 5,575 | 10 | Expected safety failure |
| `BrokenUncancelledWaiter.cfg` | Pre-`27ff3f0c` waiter control | 84,852 / 23,534 | lasso | Expected temporal failure |

The persistence reachability trace crosses the barrier with an admitted mutation. It defers a
save, schedules that save before producer release, parks a waiter, and returns a storage failure.
The worker then becomes idle and resumes the waiter. The runtime completes the flush normally.

The lifecycle reachability trace uses two foreground scenes and two background generations. It
denies and reconciles a queued coordinator transition. It also expires a busy flush with a
registered waiter. The cancellation task removes and resumes that waiter. A late expiration from
the first generation cannot end the second lease.

## Broken controls

`BrokenUntrackedQuiescence.cfg` models the coordinator callback before `58e15c31`. The callback is
queued before admission closes, but it owns no producer lease. The flush observes idle persistence
and no active producer. It resumes and ends the background lease without accounting for the queued
callback.

`BrokenUntrackedPostBarrier.cfg` continues that trace. The old callback enqueues preference work
after the runtime completed its flush. This violates the closed barrier directly.

`BrokenUncancelledWaiter.cfg` models the waiter before `27ff3f0c`. Foreground entry cancels the
runtime task after its initial guard. The task remains parked because no cancellation handler
removes its registered continuation. The trace can stutter while an external producer stays
suspended. The current handler does not depend on producer completion.

The two reachability configurations deliberately invert their coverage goals. Their expected
failures prove that TLC reached deferred failure, parked waiter, registered-waiter cleanup,
multi-scene, stale-generation, expiration, and coordinator-reconciliation branches.

## Fairness and exclusions

Weak fairness applies only to each scheduled flush task, each scheduled waiter-cleanup task, and
the coordinator invalidation return. These operations correspond to finite Swift tasks or one
actor call.

The model does not add fairness for producer awaits, preference storage, worker scheduling, scene
events, or UIKit expiration. Therefore, it does not claim that an uncanceled flush always
finishes. A hung store can retain work until UIKit expires the lease.

The finite producer and waiter sets represent typed `UInt64` identities without overflow. The
model reserves one unused producer identity for a queued current callback. This rule prevents a
small bound from creating an identity-exhaustion deadlock that production cannot reach.

The model allows two mutation writes. This bound represents the first write and one retry after
main-actor drift. A longer retry sequence keeps the same producer active, so it cannot cross the
closed barrier unnoticed.

The model abstracts preference values, request coalescing contents, diagnostics, and projection
presentation details. It does not model process termination, identifier overflow, or an invalid
UIKit background-task identifier.

The check used tla2tools 1.7.4 and TLC2 2.19 at revision `5a47802`.
It used Eclipse Temurin Java 21.0.8+9.
The pinned JAR SHA-256 is
`936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88`.

## Run it

From the repository root:

```sh
./tla-check BackgroundPreferencePersistence
```
