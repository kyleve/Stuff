---- MODULE BackgroundPreferencePersistence ----
EXTENDS FiniteSets, Integers, Sequences

CONSTANTS Implementation, SceneLimit, ProducerLimit, RequestLimit, FlushLimit

ASSUME /\ Implementation \in {"current", "untrackedProducer", "uncancelledWaiter"}
       /\ SceneLimit \in Nat \ {0}
       /\ ProducerLimit \in Nat
       /\ RequestLimit \in Nat \ {0}
       /\ FlushLimit \in Nat \ {0}

SceneIDs == 1..SceneLimit
ProducerIDs == 1..ProducerLimit
RequestIDs == 1..RequestLimit
FlushIDs == 1..FlushLimit
WaiterIDs == FlushIDs

ProducerKinds == {"none", "mutation", "selection", "transition"}
ProducerSources == {"none", "direct", "coordinator"}
ProducerPhases == {
    "unused",
    "suspendedBeforePublish",
    "readyToPublish",
    "waitingSave",
    "readyAfterSave",
    "suspendedAfterPublish",
    "readyToFinish",
    "done"
}

Activities == {"idle", "saving", "mutating", "mutatingAndSaving"}
WorkerPhases == {"none", "scheduled", "saving"}
RequestKinds == {"none", "coalesced", "immediate"}
RequestOwners == 0..(ProducerLimit + 1)
RequestStates == {"unused", "pending", "saving", "done"}
RequestResults == {"none", "success", "failure", "cancelled"}
DeferredFailures == {"preference", "playlist"}

RuntimePhases == {"idle", "active"}
TaskPhases == {
    "unused",
    "scheduled",
    "flushEntry",
    "handlerReady",
    "registerReady",
    "waiting",
    "resumed",
    "done"
}
TaskOutcomes == {"none", "completed", "cancelled"}
LeaseStates == {"unused", "active", "ended"}
LeaseEndCauses == {"none", "completion", "expiration", "foreground"}
CallbackPhases == {"notQueued", "queued", "rejecting", "admitted", "done"}

CoverageEvents == {
    "admitted-producer",
    "producer-at-barrier",
    "queued-request",
    "worker-saving",
    "save-failure",
    "deferred-save",
    "waiter-parked",
    "normal-flush",
    "cancel-busy",
    "cancel-cleanup",
    "registered-waiter-cleanup",
    "expired-lease",
    "multi-scene",
    "second-lease",
    "stale-generation",
    "coordinator-denied",
    "coordinator-reconciled"
}

ViolationKinds == {
    "unadmitted-post-barrier-work",
    "work-after-completed-flush",
    "unsafe-quiescent-flush",
    "wrong-generation-end"
}

VARIABLES foregroundScenes,
          admission,
          barrierState,
          producerState,
          persistenceState,
          coordinatorCallback,
          runtimeState,
          taskState,
          waiterState,
          leaseState,
          coverage,
          violations

vars == <<foregroundScenes,
          admission,
          barrierState,
          producerState,
          persistenceState,
          coordinatorCallback,
          runtimeState,
          taskState,
          waiterState,
          leaseState,
          coverage,
          violations>>

CurrentWaiterDesign == Implementation # "uncancelledWaiter"
LegacyCallbackCanPersist == Implementation = "untrackedProducer"

MutationIsActive(ps) == ps.activity \in {"mutating", "mutatingAndSaving"}

SourceQuiescent(ps, producers) ==
    /\ ps.activity = "idle"
    /\ producers.active = {}

ProtocolQuiescent(ps, producers, callback) ==
    /\ SourceQuiescent(ps, producers)
    /\ ~(LegacyCallbackCanPersist /\ callback.phase = "queued")

HandlerIsActive(phase) == phase \in {"registerReady", "waiting"}

UnusedProducers(producers) ==
    {producer \in ProducerIDs : producers.phase[producer] = "unused"}

QueueIsAvailable(ps) == ps.nextRequest \in RequestIDs

SequenceElements(sequence) ==
    {sequence[index] : index \in 1..Len(sequence)}

QueuePersistence(ps, owner, kind) ==
    IF ~QueueIsAvailable(ps)
        THEN ps
        ELSE LET request == ps.nextRequest
                 startsWorker == ps.worker = "none"
                 nextActivity ==
                     CASE ps.activity = "idle" -> "saving"
                       [] ps.activity = "mutating" -> "mutatingAndSaving"
                       [] OTHER -> ps.activity
             IN [ps EXCEPT
                    !.activity = nextActivity,
                    !.worker = IF startsWorker THEN "scheduled" ELSE @,
                    !.pending = Append(@, request),
                    !.nextRequest = @ + 1,
                    !.requestKind[request] = kind,
                    !.requestOwner[request] = owner,
                    !.requestState[request] = "pending",
                    !.workVersion = @ + 1]

PreferenceWorkViolations(owner) ==
    violations
        \cup (IF admission = "closed" /\ owner \notin barrierState.allowed
                 THEN {"unadmitted-post-barrier-work"}
                 ELSE {})
        \cup (IF admission = "closed" /\ barrierState.id \in barrierState.completed
                 THEN {"work-after-completed-flush"}
                 ELSE {})

ResumeAllWaiters(waiters) ==
    [waiters EXCEPT
        !.registered = {},
        !.resumed = @ \cup waiters.registered,
        !.resumeCount = [w \in WaiterIDs |->
            waiters.resumeCount[w] + IF w \in waiters.registered THEN 1 ELSE 0]]

SignalAllTasks(tasks, waiters, safe, version) ==
    [tasks EXCEPT
        !.signalSafe = [g \in FlushIDs |->
            IF tasks.waiter[g] \in waiters.registered
                THEN safe
                ELSE tasks.signalSafe[g]],
        !.signalVersion = [g \in FlushIDs |->
            IF tasks.waiter[g] \in waiters.registered
                THEN version
                ELSE tasks.signalVersion[g]]]

SignalOneTask(tasks, generation, safe, version) ==
    [tasks EXCEPT
        !.signalSafe[generation] = safe,
        !.signalVersion[generation] = version]

CancelWaiterState(waiters, tasks, generation) ==
    LET waiter == tasks.waiter[generation]
    IN [waiters EXCEPT
        !.cancelRequested =
            IF waiter # 0 THEN @ \cup {waiter} ELSE @,
        !.cleanup =
            IF CurrentWaiterDesign /\ waiter # 0 /\ HandlerIsActive(tasks.phase[generation])
                THEN @ \cup {waiter}
                ELSE @]

BasePersistenceAfterMutation(ps) ==
    [ps EXCEPT
        !.activity = IF ps.activity = "mutatingAndSaving" THEN "saving" ELSE "idle",
        !.mutationProducer = 0,
        !.deferred = {}]

Init ==
    /\ foregroundScenes = {}
    /\ admission = "closed"
    /\ barrierState = [id |-> 0, allowed |-> {}, completed |-> {}]
    /\ producerState = [
        phase |-> [p \in ProducerIDs |-> "unused"],
        kind |-> [p \in ProducerIDs |-> "none"],
        source |-> [p \in ProducerIDs |-> "none"],
        active |-> {},
        waitRequest |-> [p \in ProducerIDs |-> 0],
        enqueueCount |-> [p \in ProducerIDs |-> 0]
        ]
    /\ persistenceState = [
        activity |-> "idle",
        worker |-> "none",
        pending |-> <<>>,
        inFlight |-> 0,
        mutationProducer |-> 0,
        deferred |-> {},
        nextRequest |-> 1,
        requestKind |-> [r \in RequestIDs |-> "none"],
        requestOwner |-> [r \in RequestIDs |-> 0],
        requestState |-> [r \in RequestIDs |-> "unused"],
        requestResult |-> [r \in RequestIDs |-> "none"],
        workVersion |-> 0
        ]
    /\ coordinatorCallback = [
        phase |-> "notQueued",
        outstanding |-> FALSE,
        producer |-> 0
        ]
    /\ runtimeState = [phase |-> "idle", id |-> 0, cursor |-> 1]
    /\ taskState = [
        phase |-> [g \in FlushIDs |-> "unused"],
        cancelled |-> [g \in FlushIDs |-> FALSE],
        waiter |-> [g \in FlushIDs |-> 0],
        signalSafe |-> [g \in FlushIDs |-> FALSE],
        signalVersion |-> [g \in FlushIDs |-> 0],
        outcome |-> [g \in FlushIDs |-> "none"]
        ]
    /\ waiterState = [
        nextID |-> 1,
        registered |-> {},
        resumed |-> {},
        cleanup |-> {},
        cancelRequested |-> {},
        owner |-> [w \in WaiterIDs |-> 0],
        resumeCount |-> [w \in WaiterIDs |-> 0]
        ]
    /\ leaseState = [
        state |-> [g \in FlushIDs |-> "unused"],
        endCount |-> [g \in FlushIDs |-> 0],
        endCause |-> [g \in FlushIDs |-> "none"],
        expirationUsed |-> [g \in FlushIDs |-> FALSE]
        ]
    /\ coverage = {}
    /\ violations = {}

FirstControllerEntersIdle(scene) ==
    /\ scene \in SceneIDs
    /\ foregroundScenes = {}
    /\ runtimeState.phase = "idle"
    /\ runtimeState.cursor \in FlushIDs
    /\ foregroundScenes' = {scene}
    /\ admission' = "open"
    /\ barrierState' = [barrierState EXCEPT !.id = 0, !.allowed = {}]
    /\ UNCHANGED <<producerState, persistenceState, coordinatorCallback,
                    runtimeState, taskState, waiterState, leaseState,
                    coverage, violations>>

FirstControllerEntersAndCancels(scene) ==
    /\ scene \in SceneIDs
    /\ foregroundScenes = {}
    /\ runtimeState.phase = "active"
    /\ LET generation == runtimeState.id
           busyEvent == IF persistenceState.activity # "idle"
                           THEN {"cancel-busy"}
                           ELSE {}
       IN /\ foregroundScenes' = {scene}
          /\ admission' = "open"
          /\ barrierState' = [barrierState EXCEPT !.id = 0, !.allowed = {}]
          /\ runtimeState' = [phase |-> "idle", id |-> 0, cursor |-> generation + 1]
          /\ taskState' = [taskState EXCEPT !.cancelled[generation] = TRUE]
          /\ waiterState' = CancelWaiterState(waiterState, taskState, generation)
          /\ leaseState' = [leaseState EXCEPT
                !.state[generation] = "ended",
                !.endCount[generation] = @ + 1,
                !.endCause[generation] = "foreground"]
          /\ coverage' = coverage \cup busyEvent
    /\ UNCHANGED <<producerState, persistenceState, coordinatorCallback, violations>>

AdditionalControllerEnters(scene) ==
    /\ scene \in SceneIDs \ foregroundScenes
    /\ foregroundScenes # {}
    /\ foregroundScenes' = foregroundScenes \cup {scene}
    /\ coverage' = coverage \cup (IF Cardinality(foregroundScenes') > 1
                                      THEN {"multi-scene"}
                                      ELSE {})
    /\ UNCHANGED <<admission, barrierState, producerState, persistenceState,
                    coordinatorCallback, runtimeState, taskState, waiterState,
                    leaseState, violations>>

ControllerLeavesWithoutClosing(scene) ==
    /\ scene \in foregroundScenes
    /\ Cardinality(foregroundScenes) > 1
    /\ foregroundScenes' = foregroundScenes \ {scene}
    /\ UNCHANGED <<admission, barrierState, producerState, persistenceState,
                    coordinatorCallback, runtimeState, taskState, waiterState,
                    leaseState, coverage, violations>>

FinalControllerLeaves(scene) ==
    /\ foregroundScenes = {scene}
    /\ runtimeState.phase = "idle"
    /\ runtimeState.cursor \in FlushIDs
    /\ LET generation == runtimeState.cursor
           barrierCoverage == IF producerState.active # {}
                                  THEN {"producer-at-barrier"}
                                  ELSE {}
           repeatedCoverage == IF generation > 1 THEN {"second-lease"} ELSE {}
       IN /\ foregroundScenes' = {}
          /\ admission' = "closed"
          /\ barrierState' = [barrierState EXCEPT
                !.id = generation,
                !.allowed = producerState.active]
          /\ runtimeState' = [phase |-> "active", id |-> generation,
                               cursor |-> generation]
          /\ taskState' = [taskState EXCEPT
                !.phase[generation] = "scheduled",
                !.cancelled[generation] = FALSE,
                !.waiter[generation] = 0,
                !.signalSafe[generation] = FALSE,
                !.signalVersion[generation] = 0,
                !.outcome[generation] = "none"]
          /\ leaseState' = [leaseState EXCEPT
                !.state[generation] = "active",
                !.endCount[generation] = 0,
                !.endCause[generation] = "none"]
          /\ coverage' = coverage \cup barrierCoverage \cup repeatedCoverage
    /\ UNCHANGED <<producerState, persistenceState, coordinatorCallback,
                    waiterState, violations>>

BeginProducer(producer, kind) ==
    /\ producer \in ProducerIDs
    /\ kind \in ProducerKinds \ {"none"}
    /\ admission = "open"
    /\ producerState.phase[producer] = "unused"
    /\ (coordinatorCallback.phase # "queued" \/
        Cardinality(UnusedProducers(producerState)) > 1)
    /\ kind = "mutation" => ~MutationIsActive(persistenceState)
    /\ producerState' = [producerState EXCEPT
        !.phase[producer] = "suspendedBeforePublish",
        !.kind[producer] = kind,
        !.source[producer] = "direct",
        !.active = @ \cup {producer}]
    /\ persistenceState' =
        IF kind = "mutation"
            THEN [persistenceState EXCEPT
                    !.activity = IF persistenceState.activity = "saving"
                                    THEN "mutatingAndSaving"
                                    ELSE "mutating",
                    !.mutationProducer = producer,
                    !.deferred = {}]
            ELSE persistenceState
    /\ coverage' = coverage \cup {"admitted-producer"}
    /\ UNCHANGED <<foregroundScenes, admission, barrierState,
                    coordinatorCallback, runtimeState, taskState, waiterState,
                    leaseState, violations>>

ProducerReturnsFromAwait(producer) ==
    /\ producer \in ProducerIDs
    /\ producerState.phase[producer] = "suspendedBeforePublish"
    /\ producerState' = [producerState EXCEPT !.phase[producer] = "readyToPublish"]
    /\ UNCHANGED <<foregroundScenes, admission, barrierState, persistenceState,
                    coordinatorCallback, runtimeState, taskState, waiterState,
                    leaseState, coverage, violations>>

DeferPreferenceSave(failure) ==
    /\ failure \in DeferredFailures
    /\ MutationIsActive(persistenceState)
    /\ persistenceState' = [persistenceState EXCEPT !.deferred = @ \cup {failure}]
    /\ coverage' = coverage \cup {"deferred-save"}
    /\ UNCHANGED <<foregroundScenes, admission, barrierState, producerState,
                    coordinatorCallback, runtimeState, taskState, waiterState,
                    leaseState, violations>>

PublishMutation(producer) ==
    /\ producer \in ProducerIDs
    /\ producerState.phase[producer] = "readyToPublish"
    /\ producerState.kind[producer] = "mutation"
    /\ QueueIsAvailable(persistenceState)
    /\ LET request == persistenceState.nextRequest
       IN /\ producerState' = [producerState EXCEPT
                !.phase[producer] = "waitingSave",
                !.waitRequest[producer] = request,
                !.enqueueCount[producer] = @ + 1]
          /\ persistenceState' = QueuePersistence(
                persistenceState,
                producer,
                "immediate"
             )
    /\ coverage' = coverage \cup {"queued-request"}
    /\ violations' = PreferenceWorkViolations(producer)
    /\ UNCHANGED <<foregroundScenes, admission, barrierState,
                    coordinatorCallback, runtimeState, taskState, waiterState,
                    leaseState>>

PublishNonmutationWhileMutating(producer) ==
    /\ producer \in ProducerIDs
    /\ producerState.phase[producer] = "readyToPublish"
    /\ producerState.kind[producer] \in {"selection", "transition"}
    /\ MutationIsActive(persistenceState)
    /\ LET isSelection == producerState.kind[producer] = "selection"
           nextActive == IF isSelection
                            THEN producerState.active \ {producer}
                            ELSE producerState.active
       IN /\ producerState' = [producerState EXCEPT
                !.phase[producer] = IF isSelection THEN "done" ELSE "suspendedAfterPublish",
                !.active = nextActive]
          /\ persistenceState' = [persistenceState EXCEPT
                !.deferred = @ \cup {"playlist"}]
          /\ coordinatorCallback' = coordinatorCallback
          /\ coverage' = coverage \cup {"deferred-save"}
    /\ UNCHANGED <<foregroundScenes, admission, barrierState, runtimeState,
                    taskState, waiterState, leaseState, violations>>

PublishNonmutation(producer) ==
    /\ producer \in ProducerIDs
    /\ producerState.phase[producer] = "readyToPublish"
    /\ producerState.kind[producer] \in {"selection", "transition"}
    /\ ~MutationIsActive(persistenceState)
    /\ QueueIsAvailable(persistenceState)
    /\ LET isSelection == producerState.kind[producer] = "selection"
           nextActive == IF isSelection
                            THEN producerState.active \ {producer}
                            ELSE producerState.active
       IN /\ producerState' = [producerState EXCEPT
                !.phase[producer] = IF isSelection THEN "done" ELSE "suspendedAfterPublish",
                !.active = nextActive,
                !.enqueueCount[producer] = @ + 1]
          /\ persistenceState' = QueuePersistence(
                persistenceState,
                producer,
                "coalesced"
             )
    /\ coverage' = coverage \cup {"queued-request"}
    /\ violations' = PreferenceWorkViolations(producer)
    /\ UNCHANGED <<foregroundScenes, admission, barrierState,
                    coordinatorCallback, runtimeState, taskState, waiterState,
                    leaseState>>

SavedMutationCanContinue(producer) ==
    /\ producer \in ProducerIDs
    /\ producerState.phase[producer] = "waitingSave"
    /\ producerState.waitRequest[producer] \in RequestIDs
    /\ persistenceState.requestState[producerState.waitRequest[producer]] = "done"
    /\ producerState' = [producerState EXCEPT !.phase[producer] = "readyAfterSave"]
    /\ UNCHANGED <<foregroundScenes, admission, barrierState, persistenceState,
                    coordinatorCallback, runtimeState, taskState, waiterState,
                    leaseState, coverage, violations>>

RetryMutation(producer) ==
    /\ producer \in ProducerIDs
    /\ producerState.phase[producer] = "readyAfterSave"
    /\ producerState.kind[producer] = "mutation"
    /\ producerState.enqueueCount[producer] < 2
    /\ QueueIsAvailable(persistenceState)
    /\ LET request == persistenceState.nextRequest
       IN /\ producerState' = [producerState EXCEPT
                !.phase[producer] = "waitingSave",
                !.waitRequest[producer] = request,
                !.enqueueCount[producer] = @ + 1]
          /\ persistenceState' = QueuePersistence(
                persistenceState,
                producer,
                "immediate"
             )
    /\ coverage' = coverage \cup {"queued-request"}
    /\ violations' = PreferenceWorkViolations(producer)
    /\ UNCHANGED <<foregroundScenes, admission, barrierState,
                    coordinatorCallback, runtimeState, taskState, waiterState,
                    leaseState>>

PublishSavedMutation(producer) ==
    /\ producer \in ProducerIDs
    /\ producerState.phase[producer] = "readyAfterSave"
    /\ producerState.kind[producer] = "mutation"
    /\ producerState' = [producerState EXCEPT
        !.phase[producer] = "suspendedAfterPublish"]
    /\ UNCHANGED <<foregroundScenes, admission, barrierState, persistenceState,
                    coordinatorCallback, runtimeState, taskState, waiterState,
                    leaseState, coverage, violations>>

PostPublicationAwaitReturns(producer) ==
    /\ producer \in ProducerIDs
    /\ producerState.phase[producer] = "suspendedAfterPublish"
    /\ producerState' = [producerState EXCEPT !.phase[producer] = "readyToFinish"]
    /\ UNCHANGED <<foregroundScenes, admission, barrierState, persistenceState,
                    coordinatorCallback, runtimeState, taskState, waiterState,
                    leaseState, coverage, violations>>

FinishNonmutationProducer(producer) ==
    /\ producer \in ProducerIDs
    /\ producerState.kind[producer] \in {"selection", "transition"}
    /\ producerState.phase[producer] \in {"suspendedBeforePublish", "readyToPublish",
                                           "readyToFinish"}
    /\ LET nextActive == producerState.active \ {producer}
           nextProducerState == [producerState EXCEPT
                !.phase[producer] = "done",
                !.active = nextActive]
           nextCallback ==
                IF producerState.source[producer] = "coordinator"
                    THEN [coordinatorCallback EXCEPT
                            !.phase = "done",
                            !.outstanding = FALSE,
                            !.producer = 0]
                    ELSE coordinatorCallback
           becomesQuiescent ==
                persistenceState.activity = "idle" /\ nextActive = {}
       IN /\ producerState' = nextProducerState
          /\ coordinatorCallback' = nextCallback
          /\ waiterState' = IF becomesQuiescent
                                THEN ResumeAllWaiters(waiterState)
                                ELSE waiterState
          /\ taskState' = IF becomesQuiescent
                              THEN SignalAllTasks(
                                    taskState,
                                    waiterState,
                                    ProtocolQuiescent(
                                        persistenceState,
                                        nextProducerState,
                                        nextCallback
                                    ),
                                    persistenceState.workVersion
                                   )
                              ELSE taskState
    /\ UNCHANGED <<foregroundScenes, admission, barrierState, persistenceState,
                    runtimeState, leaseState, coverage, violations>>

FinishMutationProducer(producer, persistDeferred) ==
    /\ producer \in ProducerIDs
    /\ persistDeferred \in BOOLEAN
    /\ producerState.kind[producer] = "mutation"
    /\ producerState.phase[producer] \in {"suspendedBeforePublish", "readyToPublish",
                                           "readyToFinish"}
    /\ persistenceState.mutationProducer = producer
    /\ (~persistDeferred \/ persistenceState.deferred = {} \/
        QueueIsAvailable(BasePersistenceAfterMutation(persistenceState)))
    /\ LET nextActive == producerState.active \ {producer}
           nextProducerState == [producerState EXCEPT
                !.phase[producer] = "done",
                !.active = nextActive]
           basePersistence == BasePersistenceAfterMutation(persistenceState)
           writesDeferred == persistDeferred /\ persistenceState.deferred # {}
           nextPersistence ==
                IF writesDeferred
                    THEN QueuePersistence(basePersistence, producer, "coalesced")
                    ELSE basePersistence
           becomesQuiescent ==
                nextPersistence.activity = "idle" /\ nextActive = {}
       IN /\ producerState' = nextProducerState
          /\ persistenceState' = nextPersistence
          /\ waiterState' = IF becomesQuiescent
                                THEN ResumeAllWaiters(waiterState)
                                ELSE waiterState
          /\ taskState' = IF becomesQuiescent
                              THEN SignalAllTasks(
                                    taskState,
                                    waiterState,
                                    ProtocolQuiescent(
                                        nextPersistence,
                                        nextProducerState,
                                        coordinatorCallback
                                    ),
                                    nextPersistence.workVersion
                                   )
                              ELSE taskState
          /\ coverage' = coverage \cup (IF writesDeferred
                                            THEN {"queued-request"}
                                            ELSE {})
          /\ violations' = IF writesDeferred
                               THEN PreferenceWorkViolations(producer)
                               ELSE violations
    /\ UNCHANGED <<foregroundScenes, admission, barrierState,
                    coordinatorCallback, runtimeState, leaseState>>

QueueCoordinatorCallback ==
    /\ coordinatorCallback.phase = "notQueued"
    /\ foregroundScenes # {}
    /\ (LegacyCallbackCanPersist \/
        \E producer \in ProducerIDs : producerState.phase[producer] = "unused")
    /\ coordinatorCallback' = [
        phase |-> "queued",
        outstanding |-> TRUE,
        producer |-> 0
        ]
    /\ UNCHANGED <<foregroundScenes, admission, barrierState, producerState,
                    persistenceState, runtimeState, taskState, waiterState,
                    leaseState, coverage, violations>>

AdmitCoordinatorCallback(producer) ==
    /\ ~LegacyCallbackCanPersist
    /\ coordinatorCallback.phase = "queued"
    /\ admission = "open"
    /\ producer \in ProducerIDs
    /\ producerState.phase[producer] = "unused"
    /\ producerState' = [producerState EXCEPT
        !.phase[producer] = "suspendedBeforePublish",
        !.kind[producer] = "transition",
        !.source[producer] = "coordinator",
        !.active = @ \cup {producer}]
    /\ coordinatorCallback' = [coordinatorCallback EXCEPT
        !.phase = "admitted",
        !.producer = producer]
    /\ coverage' = coverage \cup {"admitted-producer"}
    /\ UNCHANGED <<foregroundScenes, admission, barrierState, persistenceState,
                    runtimeState, taskState, waiterState, leaseState, violations>>

RejectCoordinatorCallback ==
    /\ ~LegacyCallbackCanPersist
    /\ coordinatorCallback.phase = "queued"
    /\ admission = "closed"
    /\ coordinatorCallback' = [coordinatorCallback EXCEPT !.phase = "rejecting"]
    /\ coverage' = coverage \cup {"coordinator-denied"}
    /\ UNCHANGED <<foregroundScenes, admission, barrierState, producerState,
                    persistenceState, runtimeState, taskState, waiterState,
                    leaseState, violations>>

CoordinatorInvalidationReturns ==
    /\ coordinatorCallback.phase = "rejecting"
    /\ coordinatorCallback' = [
        phase |-> "done",
        outstanding |-> FALSE,
        producer |-> 0
        ]
    /\ coverage' = coverage \cup {"coordinator-reconciled"}
    /\ UNCHANGED <<foregroundScenes, admission, barrierState, producerState,
                    persistenceState, runtimeState, taskState, waiterState,
                    leaseState, violations>>

ApplyLegacyCoordinatorCallback ==
    /\ LegacyCallbackCanPersist
    /\ coordinatorCallback.phase = "queued"
    /\ ~MutationIsActive(persistenceState)
    /\ QueueIsAvailable(persistenceState)
    /\ persistenceState' = QueuePersistence(
        persistenceState,
        ProducerLimit + 1,
        "coalesced"
       )
    /\ coordinatorCallback' = [
        phase |-> "done",
        outstanding |-> FALSE,
        producer |-> 0
        ]
    /\ coverage' = coverage \cup {"queued-request"}
    /\ violations' = PreferenceWorkViolations(ProducerLimit + 1)
    /\ UNCHANGED <<foregroundScenes, admission, barrierState, producerState,
                    runtimeState, taskState, waiterState, leaseState>>

StartWorker ==
    /\ persistenceState.worker = "scheduled"
    /\ Len(persistenceState.pending) > 0
    /\ LET request == Head(persistenceState.pending)
       IN persistenceState' = [persistenceState EXCEPT
            !.worker = "saving",
            !.pending = Tail(@),
            !.inFlight = request,
            !.requestState[request] = "saving"]
    /\ coverage' = coverage \cup {"worker-saving"}
    /\ UNCHANGED <<foregroundScenes, admission, barrierState, producerState,
                    coordinatorCallback, runtimeState, taskState, waiterState,
                    leaseState, violations>>

SaveReturns(result) ==
    /\ result \in RequestResults \ {"none"}
    /\ persistenceState.worker = "saving"
    /\ persistenceState.inFlight \in RequestIDs
    /\ LET completed == persistenceState.inFlight
           hasNext == Len(persistenceState.pending) > 0
           nextRequest == IF hasNext THEN Head(persistenceState.pending) ELSE 0
           finalActivity ==
                IF hasNext
                    THEN persistenceState.activity
                    ELSE CASE persistenceState.activity = "saving" -> "idle"
                           [] persistenceState.activity = "mutatingAndSaving" -> "mutating"
           completedPersistence == [persistenceState EXCEPT
                !.activity = finalActivity,
                !.worker = IF hasNext THEN "saving" ELSE "none",
                !.pending = IF hasNext THEN Tail(@) ELSE <<>>,
                !.inFlight = nextRequest,
                !.requestState[completed] = "done",
                !.requestResult[completed] = result]
           nextPersistence ==
                IF hasNext
                    THEN [completedPersistence EXCEPT
                            !.requestState[nextRequest] = "saving"]
                    ELSE completedPersistence
           becomesQuiescent ==
                nextPersistence.activity = "idle" /\ producerState.active = {}
       IN /\ persistenceState' = nextPersistence
          /\ waiterState' = IF becomesQuiescent
                                THEN ResumeAllWaiters(waiterState)
                                ELSE waiterState
          /\ taskState' = IF becomesQuiescent
                              THEN SignalAllTasks(
                                    taskState,
                                    waiterState,
                                    ProtocolQuiescent(
                                        nextPersistence,
                                        producerState,
                                        coordinatorCallback
                                    ),
                                    nextPersistence.workVersion
                                   )
                              ELSE taskState
          /\ coverage' = coverage \cup (IF result = "failure"
                                            THEN {"save-failure"}
                                            ELSE {})
    /\ UNCHANGED <<foregroundScenes, admission, barrierState, producerState,
                    coordinatorCallback, runtimeState, leaseState, violations>>

FlushRuntimeGuard(generation) ==
    /\ generation \in FlushIDs
    /\ taskState.phase[generation] = "scheduled"
    /\ taskState' = [taskState EXCEPT
        !.phase[generation] = IF taskState.cancelled[generation]
                                 THEN "done"
                                 ELSE "flushEntry",
        !.outcome[generation] = IF taskState.cancelled[generation]
                                   THEN "cancelled"
                                   ELSE @]
    /\ coverage' = coverage \cup (IF taskState.cancelled[generation]
                                      THEN {"cancel-cleanup"}
                                      ELSE {})
    /\ UNCHANGED <<foregroundScenes, admission, barrierState, producerState,
                    persistenceState, coordinatorCallback, runtimeState,
                    waiterState, leaseState, violations>>

AllocateFlushWaiter(generation) ==
    /\ generation \in FlushIDs
    /\ taskState.phase[generation] = "flushEntry"
    /\ waiterState.nextID \in WaiterIDs
    /\ LET waiter == waiterState.nextID
           legacyStopsBeforeAllocation ==
                ~CurrentWaiterDesign /\ taskState.cancelled[generation]
       IN /\ taskState' = [taskState EXCEPT
                !.phase[generation] =
                    IF legacyStopsBeforeAllocation
                        THEN "done"
                        ELSE IF CurrentWaiterDesign THEN "handlerReady" ELSE "registerReady",
                !.waiter[generation] =
                    IF legacyStopsBeforeAllocation THEN 0 ELSE waiter,
                !.outcome[generation] =
                    IF legacyStopsBeforeAllocation THEN "cancelled" ELSE @]
          /\ waiterState' =
                IF legacyStopsBeforeAllocation
                    THEN waiterState
                    ELSE [waiterState EXCEPT
                            !.nextID = @ + 1,
                            !.owner[waiter] = generation,
                            !.cancelRequested =
                                IF taskState.cancelled[generation]
                                    THEN @ \cup {waiter}
                                    ELSE @]
          /\ coverage' = coverage \cup (IF legacyStopsBeforeAllocation
                                            THEN {"cancel-cleanup"}
                                            ELSE {})
    /\ UNCHANGED <<foregroundScenes, admission, barrierState, producerState,
                    persistenceState, coordinatorCallback, runtimeState,
                    leaseState, violations>>

EnterFlushCancellationHandler(generation) ==
    /\ CurrentWaiterDesign
    /\ generation \in FlushIDs
    /\ taskState.phase[generation] = "handlerReady"
    /\ LET waiter == taskState.waiter[generation]
       IN /\ taskState' = [taskState EXCEPT !.phase[generation] = "registerReady"]
          /\ waiterState' = [waiterState EXCEPT
                !.cancelRequested = IF taskState.cancelled[generation]
                                        THEN @ \cup {waiter}
                                        ELSE @,
                !.cleanup = IF taskState.cancelled[generation]
                                THEN @ \cup {waiter}
                                ELSE @]
    /\ UNCHANGED <<foregroundScenes, admission, barrierState, producerState,
                    persistenceState, coordinatorCallback, runtimeState,
                    leaseState, coverage, violations>>

RegisterFlushWaiter(generation) ==
    /\ generation \in FlushIDs
    /\ taskState.phase[generation] = "registerReady"
    /\ LET waiter == taskState.waiter[generation]
           isQuiescent == SourceQuiescent(persistenceState, producerState)
           cancelsSynchronously == CurrentWaiterDesign /\ taskState.cancelled[generation]
           resumesNow == isQuiescent \/ cancelsSynchronously
           safeSignal == isQuiescent /\
                ProtocolQuiescent(persistenceState, producerState, coordinatorCallback)
       IN /\ waiterState' =
                IF resumesNow
                    THEN [waiterState EXCEPT
                            !.resumed = @ \cup {waiter},
                            !.resumeCount[waiter] = @ + 1]
                    ELSE [waiterState EXCEPT !.registered = @ \cup {waiter}]
          /\ taskState' =
                IF resumesNow
                    THEN SignalOneTask(
                            [taskState EXCEPT !.phase[generation] = "resumed"],
                            generation,
                            safeSignal,
                            persistenceState.workVersion
                         )
                    ELSE [taskState EXCEPT !.phase[generation] = "waiting"]
          /\ coverage' = coverage \cup (IF resumesNow
                                            THEN {}
                                            ELSE {"waiter-parked"})
    /\ UNCHANGED <<foregroundScenes, admission, barrierState, producerState,
                    persistenceState, coordinatorCallback, runtimeState,
                    leaseState, violations>>

CleanupCanceledWaiter(waiter) ==
    /\ CurrentWaiterDesign
    /\ waiter \in waiterState.cleanup
    /\ LET wasRegistered == waiter \in waiterState.registered
           generation == waiterState.owner[waiter]
       IN /\ waiterState' = [waiterState EXCEPT
                !.cleanup = @ \ {waiter},
                !.registered = @ \ {waiter},
                !.resumed = IF wasRegistered THEN @ \cup {waiter} ELSE @,
                !.resumeCount[waiter] = IF wasRegistered THEN @ + 1 ELSE @]
          /\ taskState' =
                IF wasRegistered
                    THEN SignalOneTask(
                            taskState,
                            generation,
                            FALSE,
                            persistenceState.workVersion
                         )
                    ELSE taskState
          /\ coverage' = coverage \cup {"cancel-cleanup"}
                \cup (IF wasRegistered THEN {"registered-waiter-cleanup"} ELSE {})
    /\ UNCHANGED <<foregroundScenes, admission, barrierState, producerState,
                    persistenceState, coordinatorCallback, runtimeState,
                    leaseState, violations>>

ObserveWaiterResume(generation) ==
    /\ generation \in FlushIDs
    /\ taskState.phase[generation] = "waiting"
    /\ taskState.waiter[generation] \in waiterState.resumed
    /\ taskState' = [taskState EXCEPT !.phase[generation] = "resumed"]
    /\ UNCHANGED <<foregroundScenes, admission, barrierState, producerState,
                    persistenceState, coordinatorCallback, runtimeState,
                    waiterState, leaseState, coverage, violations>>

ReturnFromFlush(generation) ==
    /\ generation \in FlushIDs
    /\ taskState.phase[generation] = "resumed"
    /\ LET wasCancelled == taskState.cancelled[generation]
           canCompleteLease == ~wasCancelled /\
                runtimeState.phase = "active" /\ runtimeState.id = generation
           wrongGeneration == ~wasCancelled /\ runtimeState.phase = "active" /\
                runtimeState.id # generation
       IN /\ taskState' = [taskState EXCEPT
                !.phase[generation] = "done",
                !.outcome[generation] = IF wasCancelled THEN "cancelled" ELSE "completed"]
          /\ runtimeState' =
                IF canCompleteLease
                    THEN [phase |-> "idle", id |-> 0, cursor |-> generation + 1]
                    ELSE runtimeState
          /\ leaseState' =
                IF canCompleteLease
                    THEN [leaseState EXCEPT
                            !.state[generation] = "ended",
                            !.endCount[generation] = @ + 1,
                            !.endCause[generation] = "completion"]
                    ELSE leaseState
          /\ barrierState' =
                IF wasCancelled
                    THEN barrierState
                    ELSE [barrierState EXCEPT !.completed = @ \cup {generation}]
          /\ coverage' = coverage \cup (IF wasCancelled
                                            THEN {"cancel-cleanup"}
                                            ELSE {"normal-flush"})
          /\ violations' = violations
                \cup (IF ~wasCancelled /\ ~taskState.signalSafe[generation]
                         THEN {"unsafe-quiescent-flush"}
                         ELSE {})
                \cup (IF wrongGeneration
                         THEN {"wrong-generation-end"}
                         ELSE {})
    /\ UNCHANGED <<foregroundScenes, admission, producerState, persistenceState,
                    coordinatorCallback, waiterState>>

ExpireBackgroundLease(generation) ==
    /\ generation \in FlushIDs
    /\ leaseState.state[generation] # "unused"
    /\ ~leaseState.expirationUsed[generation]
    /\ LET expiresCurrent ==
                runtimeState.phase = "active" /\ runtimeState.id = generation
           rejectsStale ==
                runtimeState.phase = "active" /\ runtimeState.id # generation
           busyEvent == IF expiresCurrent /\ persistenceState.activity # "idle"
                           THEN {"cancel-busy"}
                           ELSE {}
       IN /\ runtimeState' =
                IF expiresCurrent
                    THEN [phase |-> "idle", id |-> 0, cursor |-> generation + 1]
                    ELSE runtimeState
          /\ taskState' =
                IF expiresCurrent
                    THEN [taskState EXCEPT !.cancelled[generation] = TRUE]
                    ELSE taskState
          /\ waiterState' =
                IF expiresCurrent
                    THEN CancelWaiterState(waiterState, taskState, generation)
                    ELSE waiterState
          /\ leaseState' =
                IF expiresCurrent
                    THEN [leaseState EXCEPT
                            !.state[generation] = "ended",
                            !.endCount[generation] = @ + 1,
                            !.endCause[generation] = "expiration",
                            !.expirationUsed[generation] = TRUE]
                    ELSE [leaseState EXCEPT !.expirationUsed[generation] = TRUE]
          /\ coverage' = coverage
                \cup (IF expiresCurrent THEN {"expired-lease"} ELSE {})
                \cup (IF rejectsStale THEN {"stale-generation"} ELSE {})
                \cup busyEvent
    /\ UNCHANGED <<foregroundScenes, admission, barrierState, producerState,
                    persistenceState, coordinatorCallback, violations>>

TerminalStutter ==
    /\ runtimeState.phase = "idle"
    /\ runtimeState.cursor = FlushLimit + 1
    /\ persistenceState.activity = "idle"
    /\ producerState.active = {}
    /\ coordinatorCallback.phase \in {"notQueued", "done"}
    /\ waiterState.registered = {}
    /\ waiterState.cleanup = {}
    /\ \A g \in FlushIDs : taskState.phase[g] \in {"unused", "done"}
    /\ UNCHANGED vars

ControllerAction ==
    \/ \E scene \in SceneIDs : FirstControllerEntersIdle(scene)
    \/ \E scene \in SceneIDs : FirstControllerEntersAndCancels(scene)
    \/ \E scene \in SceneIDs : AdditionalControllerEnters(scene)
    \/ \E scene \in SceneIDs : ControllerLeavesWithoutClosing(scene)
    \/ \E scene \in SceneIDs : FinalControllerLeaves(scene)

ProducerAction ==
    \/ \E producer \in ProducerIDs, kind \in ProducerKinds \ {"none"} :
        BeginProducer(producer, kind)
    \/ \E producer \in ProducerIDs : ProducerReturnsFromAwait(producer)
    \/ \E failure \in DeferredFailures : DeferPreferenceSave(failure)
    \/ \E producer \in ProducerIDs : PublishMutation(producer)
    \/ \E producer \in ProducerIDs : PublishNonmutationWhileMutating(producer)
    \/ \E producer \in ProducerIDs : PublishNonmutation(producer)
    \/ \E producer \in ProducerIDs : SavedMutationCanContinue(producer)
    \/ \E producer \in ProducerIDs : RetryMutation(producer)
    \/ \E producer \in ProducerIDs : PublishSavedMutation(producer)
    \/ \E producer \in ProducerIDs : PostPublicationAwaitReturns(producer)
    \/ \E producer \in ProducerIDs : FinishNonmutationProducer(producer)
    \/ \E producer \in ProducerIDs, persistDeferred \in BOOLEAN :
        FinishMutationProducer(producer, persistDeferred)

CoordinatorAction ==
    \/ QueueCoordinatorCallback
    \/ \E producer \in ProducerIDs : AdmitCoordinatorCallback(producer)
    \/ RejectCoordinatorCallback
    \/ CoordinatorInvalidationReturns
    \/ ApplyLegacyCoordinatorCallback

WorkerAction ==
    \/ StartWorker
    \/ \E result \in RequestResults \ {"none"} : SaveReturns(result)

FlushTaskAction(generation) ==
    \/ FlushRuntimeGuard(generation)
    \/ AllocateFlushWaiter(generation)
    \/ EnterFlushCancellationHandler(generation)
    \/ RegisterFlushWaiter(generation)
    \/ ObserveWaiterResume(generation)
    \/ ReturnFromFlush(generation)

CleanupAction(waiter) == CleanupCanceledWaiter(waiter)

Next ==
    \/ ControllerAction
    \/ ProducerAction
    \/ CoordinatorAction
    \/ WorkerAction
    \/ \E generation \in FlushIDs : FlushTaskAction(generation)
    \/ \E waiter \in WaiterIDs : CleanupAction(waiter)
    \/ \E generation \in FlushIDs : ExpireBackgroundLease(generation)
    \/ TerminalStutter

Spec ==
    /\ Init
    /\ [][Next]_vars
    /\ \A generation \in FlushIDs : WF_vars(FlushTaskAction(generation))
    /\ \A waiter \in WaiterIDs : WF_vars(CleanupAction(waiter))
    /\ WF_vars(CoordinatorInvalidationReturns)

PersistenceActivityShape ==
    /\ (persistenceState.activity = "idle")
        <=> (persistenceState.worker = "none" /\
             persistenceState.mutationProducer = 0)
    /\ (persistenceState.activity = "saving")
        <=> (persistenceState.worker # "none" /\
             persistenceState.mutationProducer = 0)
    /\ (persistenceState.activity = "mutating")
        <=> (persistenceState.worker = "none" /\
             persistenceState.mutationProducer \in ProducerIDs)
    /\ (persistenceState.activity = "mutatingAndSaving")
        <=> (persistenceState.worker # "none" /\
             persistenceState.mutationProducer \in ProducerIDs)

TypeOK ==
    /\ foregroundScenes \subseteq SceneIDs
    /\ admission \in {"open", "closed"}
    /\ barrierState \in [
        id: 0..FlushLimit,
        allowed: SUBSET ProducerIDs,
        completed: SUBSET FlushIDs
        ]
    /\ producerState \in [
        phase: [ProducerIDs -> ProducerPhases],
        kind: [ProducerIDs -> ProducerKinds],
        source: [ProducerIDs -> ProducerSources],
        active: SUBSET ProducerIDs,
        waitRequest: [ProducerIDs -> 0..RequestLimit],
        enqueueCount: [ProducerIDs -> 0..2]
        ]
    /\ persistenceState \in [
        activity: Activities,
        worker: WorkerPhases,
        pending: Seq(RequestIDs),
        inFlight: 0..RequestLimit,
        mutationProducer: 0..ProducerLimit,
        deferred: SUBSET DeferredFailures,
        nextRequest: 1..(RequestLimit + 1),
        requestKind: [RequestIDs -> RequestKinds],
        requestOwner: [RequestIDs -> RequestOwners],
        requestState: [RequestIDs -> RequestStates],
        requestResult: [RequestIDs -> RequestResults],
        workVersion: 0..RequestLimit
        ]
    /\ coordinatorCallback \in [
        phase: CallbackPhases,
        outstanding: BOOLEAN,
        producer: 0..ProducerLimit
        ]
    /\ runtimeState \in [
        phase: RuntimePhases,
        id: 0..FlushLimit,
        cursor: 1..(FlushLimit + 1)
        ]
    /\ taskState \in [
        phase: [FlushIDs -> TaskPhases],
        cancelled: [FlushIDs -> BOOLEAN],
        waiter: [FlushIDs -> 0..FlushLimit],
        signalSafe: [FlushIDs -> BOOLEAN],
        signalVersion: [FlushIDs -> 0..RequestLimit],
        outcome: [FlushIDs -> TaskOutcomes]
        ]
    /\ waiterState \in [
        nextID: 1..(FlushLimit + 1),
        registered: SUBSET WaiterIDs,
        resumed: SUBSET WaiterIDs,
        cleanup: SUBSET WaiterIDs,
        cancelRequested: SUBSET WaiterIDs,
        owner: [WaiterIDs -> 0..FlushLimit],
        resumeCount: [WaiterIDs -> 0..1]
        ]
    /\ leaseState \in [
        state: [FlushIDs -> LeaseStates],
        endCount: [FlushIDs -> 0..1],
        endCause: [FlushIDs -> LeaseEndCauses],
        expirationUsed: [FlushIDs -> BOOLEAN]
        ]
    /\ coverage \subseteq CoverageEvents
    /\ violations \subseteq ViolationKinds
    /\ PersistenceActivityShape
    /\ (admission = "open" <=> foregroundScenes # {})
    /\ (runtimeState.phase = "active" =>
        /\ foregroundScenes = {}
        /\ admission = "closed"
        /\ runtimeState.id \in FlushIDs
        /\ leaseState.state[runtimeState.id] = "active")
    /\ (runtimeState.phase = "idle" => runtimeState.id = 0)
    /\ (admission = "open" =>
        /\ barrierState.id = 0
        /\ barrierState.allowed = {})
    /\ (admission = "closed" => producerState.active \subseteq barrierState.allowed)
    /\ producerState.active = {
        p \in ProducerIDs : producerState.phase[p] \notin {"unused", "done"}
        }
    /\ (persistenceState.mutationProducer # 0 =>
        /\ persistenceState.mutationProducer \in producerState.active
        /\ producerState.kind[persistenceState.mutationProducer] = "mutation")
    /\ (persistenceState.mutationProducer = 0 => persistenceState.deferred = {})
    /\ (persistenceState.worker = "none" => persistenceState.inFlight = 0)
    /\ (persistenceState.worker = "scheduled" =>
        /\ persistenceState.inFlight = 0
        /\ Len(persistenceState.pending) > 0)
    /\ (persistenceState.worker = "saving" =>
        /\ persistenceState.inFlight \in RequestIDs
        /\ persistenceState.requestState[persistenceState.inFlight] = "saving")
    /\ \A request \in SequenceElements(persistenceState.pending) :
        persistenceState.requestState[request] = "pending"
    /\ Cardinality(SequenceElements(persistenceState.pending)) =
        Len(persistenceState.pending)
    /\ waiterState.registered \cap waiterState.resumed = {}
    /\ waiterState.registered \cup waiterState.resumed \cup waiterState.cleanup
        \subseteq 1..(waiterState.nextID - 1)
    /\ \A generation \in FlushIDs :
        taskState.waiter[generation] # 0 =>
            /\ waiterState.owner[taskState.waiter[generation]] = generation
            /\ taskState.waiter[generation] < waiterState.nextID
    /\ \A first, second \in FlushIDs :
        first # second /\ taskState.waiter[first] # 0 /\ taskState.waiter[second] # 0
            => taskState.waiter[first] # taskState.waiter[second]
    /\ (coordinatorCallback.phase \in {"queued", "rejecting", "admitted"}
        <=> coordinatorCallback.outstanding)
    /\ (coordinatorCallback.phase = "admitted" =>
        /\ coordinatorCallback.producer \in producerState.active
        /\ producerState.source[coordinatorCallback.producer] = "coordinator")

QuiescentFlushSafety == "unsafe-quiescent-flush" \notin violations

NoUnadmittedPostBarrierWork ==
    "unadmitted-post-barrier-work" \notin violations

NoWorkAfterCompletedFlush ==
    "work-after-completed-flush" \notin violations

WaitersResumeAtMostOnce ==
    \A waiter \in WaiterIDs : waiterState.resumeCount[waiter] <= 1

CanceledReturnHasNoRegisteredWaiter ==
    \A generation \in FlushIDs :
        taskState.outcome[generation] = "cancelled" =>
            taskState.waiter[generation] \notin waiterState.registered

LeaseEndExactlyOnce ==
    \A generation \in FlushIDs :
        /\ leaseState.endCount[generation] <= 1
        /\ (leaseState.state[generation] = "ended"
            <=> leaseState.endCount[generation] = 1)
        /\ (leaseState.state[generation] = "active"
            => leaseState.endCount[generation] = 0)

FinishedFlushReleasedLease ==
    \A generation \in FlushIDs :
        taskState.outcome[generation] # "none" =>
            leaseState.state[generation] = "ended"

ForegroundGenerationCannotEndNewerLease ==
    "wrong-generation-end" \notin violations

CanceledWaitersTerminateAndAreRemoved ==
    /\ \A generation \in FlushIDs :
        taskState.cancelled[generation] ~> taskState.phase[generation] = "done"
    /\ \A waiter \in WaiterIDs :
        waiter \in waiterState.cancelRequested ~>
            (waiter \in waiterState.resumed /\ waiter \notin waiterState.registered)

DeniedCoordinatorRequestsEventuallyReconcile ==
    coordinatorCallback.phase = "rejecting" ~>
        (coordinatorCallback.phase = "done" /\ ~coordinatorCallback.outstanding)

PersistenceCoverageNotReached ==
    ~({"admitted-producer", "producer-at-barrier", "queued-request",
       "worker-saving", "save-failure", "deferred-save", "waiter-parked",
       "normal-flush"} \subseteq coverage)

LifecycleCoverageNotReached ==
    ~({"multi-scene", "cancel-busy", "cancel-cleanup", "second-lease",
       "registered-waiter-cleanup", "stale-generation", "expired-lease",
       "coordinator-denied",
       "coordinator-reconciled"} \subseteq coverage)

====
