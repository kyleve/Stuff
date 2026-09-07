---- MODULE ProjectionContextTransition ----
EXTENDS Integers

CONSTANTS Implementation, MaxContext, MaxRevision, MaxLease

Implementations == {
    "current",
    "brokenContext",
    "brokenPair",
    "brokenFreshness",
    "brokenWriter",
    "brokenEarlyInvalidationFinish"
}
ASSUME Implementation \in Implementations
ASSUME MaxContext \in Nat \ {0}
ASSUME MaxRevision \in Nat \ {0}
ASSUME MaxLease \in Nat \ {0, 1}
ASSUME MaxLease > MaxContext

NoValue == -1
\* NoLease means that no operational writer or marks use a lease. A cleared
\* Swift placeholder can retain old lease metadata without operational content.
NoLease == 0
Contexts == 0..MaxContext
Revisions == 0..MaxRevision
Leases == 1..MaxLease
StagePhases == {
    "none",
    "preparing",
    "prepared",
    "reporting",
    "reported",
    "fadingOut",
    "committing",
    "fadingIn"
}
InvalidationPhases == {
    "idle",
    "contextRevoked",
    "leaseRenewed",
    "runtimeDrained",
    "cleanupComplete",
    "coordinatorConfigured",
    "stateRead",
    "leaseSynchronized"
}
CompletionKinds == {"worker", "report", "fade"}

NextLease(lease) == lease + 1

RevokedCompletions(phase) ==
    IF phase = "preparing" THEN {"worker"}
    ELSE IF phase = "reporting" THEN {"report"}
    ELSE IF phase \in {"fadingOut", "committing", "fadingIn"} THEN {"fade"}
    ELSE {}

VARIABLES
    context,
    inputRevision,
    coordinatorLease,
    sessionLease,
    invalidating,
    invalidationPhase,
    oldRuntimeDrained,
    cleanupComplete,
    leaseSynchronized,
    staleCompletions,
    stagePhase,
    stageContext,
    stageLease,
    stageSemanticRevision,
    stageProjectedRevision,
    bufferedRevision,
    visibleContext,
    visibleLease,
    visibleSemanticRevision,
    visibleProjectedRevision,
    invalidatedCommit,
    mismatchedCommit,
    staleInputAccepted,
    writerDuringFadeIn,
    reachedPrepared,
    reachedBlackCommit,
    reachedBufferedRevision,
    reachedInvalidationDuringPreparation,
    reachedInvalidationDuringFade,
    reachedWorkerInputRejection,
    reachedReportInputRejection,
    reachedContextRevoke,
    reachedLeaseRenewal,
    reachedRuntimeDrain,
    reachedCleanup,
    reachedCoordinatorConfigure,
    reachedStateRead,
    reachedLeaseSync,
    reachedStaleWorker,
    reachedStaleReport,
    reachedStaleFade

identityState == <<context, inputRevision, coordinatorLease, sessionLease>>

gateState == <<
    invalidating,
    invalidationPhase,
    oldRuntimeDrained,
    cleanupComplete,
    leaseSynchronized,
    staleCompletions
>>

stageState == <<
    stagePhase,
    stageContext,
    stageLease,
    stageSemanticRevision,
    stageProjectedRevision,
    bufferedRevision
>>

visibleState == <<
    visibleContext,
    visibleLease,
    visibleSemanticRevision,
    visibleProjectedRevision
>>

violationState == <<
    invalidatedCommit,
    mismatchedCommit,
    staleInputAccepted,
    writerDuringFadeIn
>>

transitionReachState == <<
    reachedPrepared,
    reachedBlackCommit,
    reachedBufferedRevision,
    reachedInvalidationDuringPreparation,
    reachedInvalidationDuringFade,
    reachedWorkerInputRejection,
    reachedReportInputRejection
>>

invalidationReachState == <<
    reachedContextRevoke,
    reachedLeaseRenewal,
    reachedRuntimeDrain,
    reachedCleanup,
    reachedCoordinatorConfigure,
    reachedStateRead,
    reachedLeaseSync
>>

staleReachState == <<reachedStaleWorker, reachedStaleReport, reachedStaleFade>>

vars == <<
    identityState,
    gateState,
    stageState,
    visibleState,
    violationState,
    transitionReachState,
    invalidationReachState,
    staleReachState
>>

Init ==
    /\ context = 0
    /\ inputRevision = 0
    /\ coordinatorLease = 1
    /\ sessionLease = 1
    /\ invalidating = FALSE
    /\ invalidationPhase = "idle"
    /\ oldRuntimeDrained = TRUE
    /\ cleanupComplete = TRUE
    /\ leaseSynchronized = TRUE
    /\ staleCompletions = {}
    /\ stagePhase = "none"
    /\ stageContext = NoValue
    /\ stageLease = NoLease
    /\ stageSemanticRevision = NoValue
    /\ stageProjectedRevision = NoValue
    /\ bufferedRevision = NoValue
    /\ visibleContext = 0
    /\ visibleLease = 1
    /\ visibleSemanticRevision = 0
    /\ visibleProjectedRevision = 0
    /\ invalidatedCommit = FALSE
    /\ mismatchedCommit = FALSE
    /\ staleInputAccepted = FALSE
    /\ writerDuringFadeIn = FALSE
    /\ reachedPrepared = FALSE
    /\ reachedBlackCommit = FALSE
    /\ reachedBufferedRevision = FALSE
    /\ reachedInvalidationDuringPreparation = FALSE
    /\ reachedInvalidationDuringFade = FALSE
    /\ reachedWorkerInputRejection = FALSE
    /\ reachedReportInputRejection = FALSE
    /\ reachedContextRevoke = FALSE
    /\ reachedLeaseRenewal = FALSE
    /\ reachedRuntimeDrain = FALSE
    /\ reachedCleanup = FALSE
    /\ reachedCoordinatorConfigure = FALSE
    /\ reachedStateRead = FALSE
    /\ reachedLeaseSync = FALSE
    /\ reachedStaleWorker = FALSE
    /\ reachedStaleReport = FALSE
    /\ reachedStaleFade = FALSE

StartPreparation ==
    /\ ~invalidating
    /\ invalidationPhase = "idle"
    /\ sessionLease = coordinatorLease
    /\ stagePhase = "none"
    /\ stagePhase' = "preparing"
    /\ stageContext' = context
    /\ stageLease' = sessionLease
    /\ stageSemanticRevision' = inputRevision
    /\ stageProjectedRevision' = NoValue
    /\ bufferedRevision' = NoValue
    /\ UNCHANGED <<
        identityState, gateState, visibleState, violationState,
        transitionReachState, invalidationReachState, staleReachState
        >>

CompleteWorker ==
    /\ stagePhase = "preparing"
    /\ ~invalidating
    /\ stageContext = context
    /\ stageLease = sessionLease
    /\ stageSemanticRevision = inputRevision \/ Implementation = "brokenFreshness"
    /\ stagePhase' = "prepared"
    /\ stageProjectedRevision' = stageSemanticRevision
    /\ staleInputAccepted' = (
        staleInputAccepted \/ stageSemanticRevision # inputRevision
        )
    /\ reachedPrepared' = TRUE
    /\ UNCHANGED <<
        identityState, gateState, visibleState,
        invalidatedCommit, mismatchedCommit, writerDuringFadeIn,
        stageContext, stageLease, stageSemanticRevision, bufferedRevision,
        reachedBlackCommit, reachedBufferedRevision,
        reachedInvalidationDuringPreparation, reachedInvalidationDuringFade,
        reachedWorkerInputRejection, reachedReportInputRejection,
        invalidationReachState, staleReachState
        >>

RejectSupersededWorkerOutput ==
    /\ Implementation # "brokenFreshness"
    /\ stagePhase = "preparing"
    /\ ~invalidating
    /\ stageContext = context
    /\ stageLease = sessionLease
    /\ stageSemanticRevision # inputRevision
    /\ stagePhase' = "none"
    /\ stageContext' = NoValue
    /\ stageLease' = NoLease
    /\ stageSemanticRevision' = NoValue
    /\ stageProjectedRevision' = NoValue
    /\ bufferedRevision' = NoValue
    /\ reachedWorkerInputRejection' = TRUE
    /\ UNCHANGED <<
        identityState, gateState, visibleState, violationState,
        reachedPrepared, reachedBlackCommit, reachedBufferedRevision,
        reachedInvalidationDuringPreparation, reachedInvalidationDuringFade,
        reachedReportInputRejection, invalidationReachState, staleReachState
        >>

CompleteStaleWorker ==
    /\ Implementation = "brokenContext"
    /\ stagePhase = "preparing"
    /\ invalidating \/ stageContext # context \/ stageLease # sessionLease
    /\ stagePhase' = "prepared"
    /\ stageProjectedRevision' = stageSemanticRevision
    /\ reachedPrepared' = TRUE
    /\ UNCHANGED <<
        identityState, gateState, visibleState, violationState,
        stageContext, stageLease, stageSemanticRevision, bufferedRevision,
        reachedBlackCommit, reachedBufferedRevision,
        reachedInvalidationDuringPreparation, reachedInvalidationDuringFade,
        reachedWorkerInputRejection, reachedReportInputRejection,
        invalidationReachState, staleReachState
        >>

BeginPreparedReport ==
    /\ stagePhase = "prepared"
    /\ stagePhase' = "reporting"
    /\ UNCHANGED <<
        identityState, gateState, visibleState, violationState,
        stageContext, stageLease, stageSemanticRevision,
        stageProjectedRevision, bufferedRevision, transitionReachState,
        invalidationReachState, staleReachState
        >>

AcceptPreparedReport ==
    /\ stagePhase = "reporting"
    /\ ~invalidating
    /\ stageContext = context
    /\ stageLease = sessionLease
    /\ stageSemanticRevision = inputRevision \/ Implementation = "brokenFreshness"
    /\ stagePhase' = "reported"
    /\ staleInputAccepted' = (
        staleInputAccepted \/ stageSemanticRevision # inputRevision
        )
    /\ UNCHANGED <<
        identityState, gateState, visibleState,
        invalidatedCommit, mismatchedCommit, writerDuringFadeIn,
        stageContext, stageLease, stageSemanticRevision,
        stageProjectedRevision, bufferedRevision, transitionReachState,
        invalidationReachState, staleReachState
        >>

RejectSupersededPreparedReport ==
    /\ Implementation # "brokenFreshness"
    /\ stagePhase = "reporting"
    /\ ~invalidating
    /\ stageContext = context
    /\ stageLease = sessionLease
    /\ stageSemanticRevision # inputRevision
    /\ stagePhase' = "none"
    /\ stageContext' = NoValue
    /\ stageLease' = NoLease
    /\ stageSemanticRevision' = NoValue
    /\ stageProjectedRevision' = NoValue
    /\ bufferedRevision' = NoValue
    /\ reachedReportInputRejection' = TRUE
    /\ UNCHANGED <<
        identityState, gateState, visibleState, violationState,
        reachedPrepared, reachedBlackCommit, reachedBufferedRevision,
        reachedInvalidationDuringPreparation, reachedInvalidationDuringFade,
        reachedWorkerInputRejection, invalidationReachState, staleReachState
        >>

AcceptStalePreparedReport ==
    /\ Implementation = "brokenContext"
    /\ stagePhase = "reporting"
    /\ invalidating \/ stageContext # context \/ stageLease # sessionLease
    /\ stagePhase' = "reported"
    /\ UNCHANGED <<
        identityState, gateState, visibleState, violationState,
        stageContext, stageLease, stageSemanticRevision,
        stageProjectedRevision, bufferedRevision, transitionReachState,
        invalidationReachState, staleReachState
        >>

RejectStalePreparedReport ==
    /\ Implementation # "brokenContext"
    /\ stagePhase = "reporting"
    /\ invalidating \/ stageContext # context \/ stageLease # sessionLease
    /\ stagePhase' = "none"
    /\ stageContext' = NoValue
    /\ stageLease' = NoLease
    /\ stageSemanticRevision' = NoValue
    /\ stageProjectedRevision' = NoValue
    /\ bufferedRevision' = NoValue
    /\ UNCHANGED <<
        identityState, gateState, visibleState, violationState,
        transitionReachState, invalidationReachState, staleReachState
        >>

BeginFadeOut ==
    /\ stagePhase = "reported"
    /\ stagePhase' = "fadingOut"
    /\ UNCHANGED <<
        identityState, gateState, visibleState, violationState,
        stageContext, stageLease, stageSemanticRevision,
        stageProjectedRevision, bufferedRevision, transitionReachState,
        invalidationReachState, staleReachState
        >>

BeginCoordinatorCommit ==
    /\ stagePhase = "fadingOut"
    /\ stagePhase' = "committing"
    /\ UNCHANGED <<
        identityState, gateState, visibleState, violationState,
        stageContext, stageLease, stageSemanticRevision,
        stageProjectedRevision, bufferedRevision, transitionReachState,
        invalidationReachState, staleReachState
        >>

UpdateTargetInput ==
    /\ ~invalidating
    /\ inputRevision < MaxRevision
    /\ inputRevision' = inputRevision + 1
    /\ bufferedRevision' =
        IF stagePhase \in {"fadingOut", "committing", "fadingIn"}
            THEN inputRevision + 1
            ELSE bufferedRevision
    /\ reachedBufferedRevision' = (
        reachedBufferedRevision \/
            stagePhase \in {"fadingOut", "committing", "fadingIn"}
        )
    /\ UNCHANGED <<
        context, coordinatorLease, sessionLease, gateState,
        stagePhase, stageContext, stageLease, stageSemanticRevision,
        stageProjectedRevision, visibleState, violationState,
        reachedPrepared, reachedBlackCommit,
        reachedInvalidationDuringPreparation, reachedInvalidationDuringFade,
        reachedWorkerInputRejection, reachedReportInputRejection,
        invalidationReachState, staleReachState
        >>

InvalidateProjectionContext ==
    /\ ~invalidating
    /\ invalidationPhase = "idle"
    /\ context < MaxContext
    /\ context' = context + 1
    /\ inputRevision' = 0
    /\ sessionLease' = NoLease
    /\ invalidating' = TRUE
    /\ invalidationPhase' = "contextRevoked"
    /\ oldRuntimeDrained' = FALSE
    /\ cleanupComplete' = FALSE
    /\ leaseSynchronized' = FALSE
    /\ staleCompletions' = staleCompletions \cup (
        IF Implementation = "brokenContext"
            THEN {}
            ELSE RevokedCompletions(stagePhase)
        )
    /\ IF Implementation = "brokenContext"
        THEN UNCHANGED stageState
        ELSE (
            /\ stagePhase' = "none"
            /\ stageContext' = NoValue
            /\ stageLease' = NoLease
            /\ stageSemanticRevision' = NoValue
            /\ stageProjectedRevision' = NoValue
            /\ bufferedRevision' = NoValue
        )
    /\ reachedInvalidationDuringPreparation' = (
        reachedInvalidationDuringPreparation \/
            stagePhase \in {"preparing", "prepared", "reporting", "reported"}
        )
    /\ reachedInvalidationDuringFade' = (
        reachedInvalidationDuringFade \/
            stagePhase \in {"fadingOut", "committing", "fadingIn"}
        )
    /\ reachedContextRevoke' = TRUE
    /\ UNCHANGED <<
        coordinatorLease, visibleState, violationState,
        reachedPrepared, reachedBlackCommit, reachedBufferedRevision,
        reachedWorkerInputRejection, reachedReportInputRejection,
        reachedLeaseRenewal, reachedRuntimeDrain, reachedCleanup,
        reachedCoordinatorConfigure, reachedStateRead, reachedLeaseSync,
        staleReachState
        >>

RenewExactActivationLease ==
    /\ invalidating
    /\ invalidationPhase = "contextRevoked"
    /\ coordinatorLease < MaxLease
    /\ coordinatorLease' = NextLease(coordinatorLease)
    /\ invalidationPhase' = "leaseRenewed"
    /\ reachedLeaseRenewal' = TRUE
    /\ UNCHANGED <<
        context, inputRevision, sessionLease, invalidating,
        oldRuntimeDrained, cleanupComplete, leaseSynchronized,
        staleCompletions, stageState, visibleState, violationState,
        transitionReachState, reachedContextRevoke, reachedRuntimeDrain,
        reachedCleanup, reachedCoordinatorConfigure, reachedStateRead,
        reachedLeaseSync, staleReachState
        >>

DrainOldRuntime ==
    /\ invalidating
    /\ invalidationPhase = "leaseRenewed"
    /\ invalidationPhase' = "runtimeDrained"
    /\ oldRuntimeDrained' = TRUE
    /\ reachedRuntimeDrain' = TRUE
    /\ UNCHANGED <<
        identityState, invalidating, cleanupComplete, leaseSynchronized,
        staleCompletions, stageState, visibleState, violationState,
        transitionReachState, reachedContextRevoke, reachedLeaseRenewal,
        reachedCleanup, reachedCoordinatorConfigure, reachedStateRead,
        reachedLeaseSync, staleReachState
        >>

CompleteObserverOrSourceCleanup ==
    /\ invalidating
    /\ invalidationPhase = "runtimeDrained"
    /\ invalidationPhase' = "cleanupComplete"
    /\ cleanupComplete' = TRUE
    /\ visibleContext' = context
    /\ visibleLease' = NoLease
    /\ visibleSemanticRevision' = inputRevision
    /\ visibleProjectedRevision' = inputRevision
    /\ reachedCleanup' = TRUE
    /\ UNCHANGED <<
        identityState, invalidating, oldRuntimeDrained, leaseSynchronized,
        staleCompletions, stageState, violationState, transitionReachState,
        reachedContextRevoke, reachedLeaseRenewal, reachedRuntimeDrain,
        reachedCoordinatorConfigure, reachedStateRead, reachedLeaseSync,
        staleReachState
        >>

ConfigureCoordinator ==
    /\ invalidating
    /\ invalidationPhase = "cleanupComplete"
    /\ invalidationPhase' = "coordinatorConfigured"
    /\ reachedCoordinatorConfigure' = TRUE
    /\ UNCHANGED <<
        identityState, invalidating, oldRuntimeDrained, cleanupComplete,
        leaseSynchronized, staleCompletions, stageState, visibleState,
        violationState, transitionReachState, reachedContextRevoke,
        reachedLeaseRenewal, reachedRuntimeDrain, reachedCleanup,
        reachedStateRead, reachedLeaseSync, staleReachState
        >>

ReadCoordinatorState ==
    /\ invalidating
    /\ invalidationPhase = "coordinatorConfigured"
    /\ invalidationPhase' = "stateRead"
    /\ reachedStateRead' = TRUE
    /\ UNCHANGED <<
        identityState, invalidating, oldRuntimeDrained, cleanupComplete,
        leaseSynchronized, staleCompletions, stageState, visibleState,
        violationState, transitionReachState, reachedContextRevoke,
        reachedLeaseRenewal, reachedRuntimeDrain, reachedCleanup,
        reachedCoordinatorConfigure, reachedLeaseSync, staleReachState
        >>

SynchronizeAuthoritativeLease ==
    /\ invalidating
    /\ invalidationPhase = "stateRead"
    /\ sessionLease' = coordinatorLease
    /\ invalidationPhase' = "leaseSynchronized"
    /\ leaseSynchronized' = TRUE
    /\ reachedLeaseSync' = TRUE
    /\ UNCHANGED <<
        context, inputRevision, coordinatorLease, invalidating,
        oldRuntimeDrained, cleanupComplete, staleCompletions,
        stageState, visibleState, violationState, transitionReachState,
        reachedContextRevoke, reachedLeaseRenewal, reachedRuntimeDrain,
        reachedCleanup, reachedCoordinatorConfigure, reachedStateRead,
        staleReachState
        >>

FinishInvalidation ==
    /\ invalidating
    /\ invalidationPhase = "leaseSynchronized"
    /\ oldRuntimeDrained
    /\ cleanupComplete
    /\ leaseSynchronized
    /\ sessionLease = coordinatorLease
    /\ invalidating' = FALSE
    /\ invalidationPhase' = "idle"
    /\ stagePhase' = "none"
    /\ stageContext' = NoValue
    /\ stageLease' = NoLease
    /\ stageSemanticRevision' = NoValue
    /\ stageProjectedRevision' = NoValue
    /\ bufferedRevision' = NoValue
    /\ UNCHANGED <<
        identityState, oldRuntimeDrained, cleanupComplete,
        leaseSynchronized, staleCompletions, visibleState, violationState,
        transitionReachState, invalidationReachState, staleReachState
        >>

FinishInvalidationEarly ==
    /\ Implementation = "brokenEarlyInvalidationFinish"
    /\ invalidating
    /\ invalidationPhase = "runtimeDrained"
    /\ invalidating' = FALSE
    /\ invalidationPhase' = "idle"
    /\ UNCHANGED <<
        identityState, oldRuntimeDrained, cleanupComplete,
        leaseSynchronized, staleCompletions, stageState,
        visibleState, violationState,
        transitionReachState, invalidationReachState, staleReachState
        >>

CompleteRevokedWorker ==
    /\ "worker" \in staleCompletions
    /\ staleCompletions' = staleCompletions \ {"worker"}
    /\ reachedStaleWorker' = TRUE
    /\ UNCHANGED <<
        identityState, invalidating, invalidationPhase,
        oldRuntimeDrained, cleanupComplete, leaseSynchronized,
        stageState, visibleState, violationState, transitionReachState,
        invalidationReachState, reachedStaleReport, reachedStaleFade
        >>

CompleteRevokedReport ==
    /\ "report" \in staleCompletions
    /\ staleCompletions' = staleCompletions \ {"report"}
    /\ reachedStaleReport' = TRUE
    /\ UNCHANGED <<
        identityState, invalidating, invalidationPhase,
        oldRuntimeDrained, cleanupComplete, leaseSynchronized,
        stageState, visibleState, violationState, transitionReachState,
        invalidationReachState, reachedStaleWorker, reachedStaleFade
        >>

CompleteRevokedFade ==
    /\ "fade" \in staleCompletions
    /\ staleCompletions' = staleCompletions \ {"fade"}
    /\ reachedStaleFade' = TRUE
    /\ UNCHANGED <<
        identityState, invalidating, invalidationPhase,
        oldRuntimeDrained, cleanupComplete, leaseSynchronized,
        stageState, visibleState, violationState, transitionReachState,
        invalidationReachState, reachedStaleWorker, reachedStaleReport
        >>

CommitCurrentPreparedPair ==
    /\ Implementation # "brokenPair"
    /\ stagePhase = "committing"
    /\ ~invalidating
    /\ stageContext = context
    /\ stageLease = coordinatorLease
    /\ stageLease = sessionLease
    /\ stagePhase' = "fadingIn"
    /\ visibleContext' = stageContext
    /\ visibleLease' = stageLease
    /\ visibleSemanticRevision' = stageSemanticRevision
    /\ visibleProjectedRevision' = stageProjectedRevision
    /\ reachedBlackCommit' = TRUE
    /\ UNCHANGED <<
        identityState, gateState, stageContext, stageLease,
        stageSemanticRevision, stageProjectedRevision, bufferedRevision,
        violationState, reachedPrepared, reachedBufferedRevision,
        reachedInvalidationDuringPreparation, reachedInvalidationDuringFade,
        reachedWorkerInputRejection, reachedReportInputRejection,
        invalidationReachState, staleReachState
        >>

CommitBrokenPair ==
    /\ Implementation = "brokenPair"
    /\ stagePhase = "committing"
    /\ ~invalidating
    /\ stageContext = context
    /\ stageLease = coordinatorLease
    /\ stageLease = sessionLease
    /\ stagePhase' = "fadingIn"
    /\ visibleContext' = stageContext
    /\ visibleLease' = stageLease
    /\ visibleSemanticRevision' = inputRevision
    /\ visibleProjectedRevision' = stageProjectedRevision
    /\ mismatchedCommit' = (
        mismatchedCommit \/ inputRevision # stageProjectedRevision
        )
    /\ reachedBlackCommit' = TRUE
    /\ UNCHANGED <<
        identityState, gateState, stageContext, stageLease,
        stageSemanticRevision, stageProjectedRevision, bufferedRevision,
        invalidatedCommit, staleInputAccepted, writerDuringFadeIn, reachedPrepared,
        reachedBufferedRevision, reachedInvalidationDuringPreparation,
        reachedInvalidationDuringFade, reachedWorkerInputRejection,
        reachedReportInputRejection, invalidationReachState, staleReachState
        >>

CommitBrokenContext ==
    /\ Implementation = "brokenContext"
    /\ stagePhase = "committing"
    /\ invalidating \/
        stageContext # context \/
        stageLease # coordinatorLease \/
        stageLease # sessionLease
    /\ stagePhase' = "fadingIn"
    /\ visibleContext' = stageContext
    /\ visibleLease' = stageLease
    /\ visibleSemanticRevision' = stageSemanticRevision
    /\ visibleProjectedRevision' = stageProjectedRevision
    /\ invalidatedCommit' = TRUE
    /\ reachedBlackCommit' = TRUE
    /\ UNCHANGED <<
        identityState, gateState, stageContext, stageLease,
        stageSemanticRevision, stageProjectedRevision, bufferedRevision,
        mismatchedCommit, staleInputAccepted, writerDuringFadeIn, reachedPrepared,
        reachedBufferedRevision, reachedInvalidationDuringPreparation,
        reachedInvalidationDuringFade, reachedWorkerInputRejection,
        reachedReportInputRejection, invalidationReachState, staleReachState
        >>

RejectInvalidatedCommit ==
    /\ Implementation # "brokenContext"
    /\ stagePhase = "committing"
    /\ invalidating \/
        stageContext # context \/
        stageLease # coordinatorLease \/
        stageLease # sessionLease
    /\ stagePhase' = "none"
    /\ stageContext' = NoValue
    /\ stageLease' = NoLease
    /\ stageSemanticRevision' = NoValue
    /\ stageProjectedRevision' = NoValue
    /\ bufferedRevision' = NoValue
    /\ UNCHANGED <<
        identityState, gateState, visibleState, violationState,
        transitionReachState, invalidationReachState, staleReachState
        >>

PublishDuringFadeIn ==
    /\ Implementation = "brokenWriter"
    /\ stagePhase = "fadingIn"
    /\ bufferedRevision # NoValue
    /\ bufferedRevision' = NoValue
    /\ visibleContext' = context
    /\ visibleLease' = coordinatorLease
    /\ visibleSemanticRevision' = bufferedRevision
    /\ visibleProjectedRevision' = bufferedRevision
    /\ writerDuringFadeIn' = TRUE
    /\ UNCHANGED <<
        identityState, gateState, stagePhase, stageContext, stageLease,
        stageSemanticRevision, stageProjectedRevision,
        invalidatedCommit, mismatchedCommit, staleInputAccepted,
        transitionReachState,
        invalidationReachState, staleReachState
        >>

CompleteFadeIn ==
    /\ stagePhase = "fadingIn"
    /\ stagePhase' = "none"
    /\ stageContext' = NoValue
    /\ stageLease' = NoLease
    /\ stageSemanticRevision' = NoValue
    /\ stageProjectedRevision' = NoValue
    /\ bufferedRevision' = NoValue
    /\ visibleSemanticRevision' =
        IF bufferedRevision = NoValue
            THEN visibleSemanticRevision
            ELSE bufferedRevision
    /\ visibleProjectedRevision' =
        IF bufferedRevision = NoValue
            THEN visibleProjectedRevision
            ELSE bufferedRevision
    /\ UNCHANGED <<
        identityState, gateState, visibleContext, visibleLease, violationState,
        transitionReachState, invalidationReachState, staleReachState
        >>

Next ==
    \/ StartPreparation
    \/ CompleteWorker
    \/ RejectSupersededWorkerOutput
    \/ CompleteStaleWorker
    \/ BeginPreparedReport
    \/ AcceptPreparedReport
    \/ RejectSupersededPreparedReport
    \/ AcceptStalePreparedReport
    \/ RejectStalePreparedReport
    \/ BeginFadeOut
    \/ BeginCoordinatorCommit
    \/ UpdateTargetInput
    \/ InvalidateProjectionContext
    \/ RenewExactActivationLease
    \/ DrainOldRuntime
    \/ CompleteObserverOrSourceCleanup
    \/ ConfigureCoordinator
    \/ ReadCoordinatorState
    \/ SynchronizeAuthoritativeLease
    \/ FinishInvalidation
    \/ FinishInvalidationEarly
    \/ CompleteRevokedWorker
    \/ CompleteRevokedReport
    \/ CompleteRevokedFade
    \/ CommitCurrentPreparedPair
    \/ CommitBrokenPair
    \/ CommitBrokenContext
    \/ RejectInvalidatedCommit
    \/ PublishDuringFadeIn
    \/ CompleteFadeIn

Spec == Init /\ [][Next]_vars

TypeOK ==
    /\ context \in Contexts
    /\ inputRevision \in Revisions
    /\ coordinatorLease \in Leases
    /\ sessionLease \in Leases \cup {NoLease}
    /\ invalidating \in BOOLEAN
    /\ invalidationPhase \in InvalidationPhases
    /\ oldRuntimeDrained \in BOOLEAN
    /\ cleanupComplete \in BOOLEAN
    /\ leaseSynchronized \in BOOLEAN
    /\ staleCompletions \in SUBSET CompletionKinds
    /\ stagePhase \in StagePhases
    /\ stageContext \in Contexts \cup {NoValue}
    /\ stageLease \in Leases \cup {NoLease}
    /\ stageSemanticRevision \in Revisions \cup {NoValue}
    /\ stageProjectedRevision \in Revisions \cup {NoValue}
    /\ bufferedRevision \in Revisions \cup {NoValue}
    /\ visibleContext \in Contexts
    /\ visibleLease \in Leases \cup {NoLease}
    /\ visibleSemanticRevision \in Revisions
    /\ visibleProjectedRevision \in Revisions
    /\ invalidatedCommit \in BOOLEAN
    /\ mismatchedCommit \in BOOLEAN
    /\ staleInputAccepted \in BOOLEAN
    /\ writerDuringFadeIn \in BOOLEAN
    /\ reachedPrepared \in BOOLEAN
    /\ reachedBlackCommit \in BOOLEAN
    /\ reachedBufferedRevision \in BOOLEAN
    /\ reachedInvalidationDuringPreparation \in BOOLEAN
    /\ reachedInvalidationDuringFade \in BOOLEAN
    /\ reachedWorkerInputRejection \in BOOLEAN
    /\ reachedReportInputRejection \in BOOLEAN
    /\ reachedContextRevoke \in BOOLEAN
    /\ reachedLeaseRenewal \in BOOLEAN
    /\ reachedRuntimeDrain \in BOOLEAN
    /\ reachedCleanup \in BOOLEAN
    /\ reachedCoordinatorConfigure \in BOOLEAN
    /\ reachedStateRead \in BOOLEAN
    /\ reachedLeaseSync \in BOOLEAN
    /\ reachedStaleWorker \in BOOLEAN
    /\ reachedStaleReport \in BOOLEAN
    /\ reachedStaleFade \in BOOLEAN

StagingShape ==
    /\ (stagePhase = "none") =>
        /\ stageContext = NoValue
        /\ stageLease = NoLease
        /\ stageSemanticRevision = NoValue
        /\ stageProjectedRevision = NoValue
    /\ (stagePhase = "preparing") =>
        /\ stageContext \in Contexts
        /\ stageLease \in Leases
        /\ stageSemanticRevision \in Revisions
        /\ stageProjectedRevision = NoValue
    /\ (stagePhase \in StagePhases \ {"none", "preparing"}) =>
        /\ stageContext \in Contexts
        /\ stageLease \in Leases
        /\ stageSemanticRevision \in Revisions
        /\ stageProjectedRevision = stageSemanticRevision

OperationalVisibleIdentity ==
    ~invalidating /\ visibleLease # NoLease =>
        /\ visibleContext = context
        /\ visibleLease = coordinatorLease
        /\ sessionLease = coordinatorLease

ExactVisiblePair ==
    visibleSemanticRevision = visibleProjectedRevision

NoInvalidatedContextCommit ==
    ~invalidatedCommit

NoMismatchedCommit ==
    ~mismatchedCommit

NoStaleInputAcceptance ==
    ~staleInputAccepted

NoWriterDuringFadeIn ==
    ~writerDuringFadeIn

InvalidationGateHoldsUntilCleanupAndLeaseSync ==
    /\ (invalidationPhase # "idle") => invalidating
    /\ ~invalidating =>
        /\ invalidationPhase = "idle"
        /\ oldRuntimeDrained
        /\ cleanupComplete
        /\ leaseSynchronized
        /\ sessionLease = coordinatorLease

RequiredPathsNotAllReached ==
    ~(reachedPrepared /\
      reachedBlackCommit /\
      reachedBufferedRevision /\
      reachedInvalidationDuringPreparation /\
      reachedInvalidationDuringFade /\
      reachedContextRevoke /\
      reachedLeaseRenewal /\
      reachedRuntimeDrain /\
      reachedCleanup /\
      reachedCoordinatorConfigure /\
      reachedStateRead /\
      reachedLeaseSync)

StaleWorkerCompletionNotReached == ~reachedStaleWorker
StaleReportCompletionNotReached == ~reachedStaleReport
StaleFadeCompletionNotReached == ~reachedStaleFade
WorkerInputRejectionNotReached == ~reachedWorkerInputRejection
ReportInputRejectionNotReached == ~reachedReportInputRejection

====
