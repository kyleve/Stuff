---- MODULE ProjectionContextTransition ----
EXTENDS Integers

CONSTANTS Implementation, MaxContext, MaxRevision, MaxLease

Implementations == {"current", "brokenContext", "brokenPair", "brokenWriter"}
ASSUME Implementation \in Implementations
ASSUME MaxContext \in Nat \ {0}
ASSUME MaxRevision \in Nat \ {0}
ASSUME MaxLease \in Nat \ {0, 1}

NoValue == -1
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

NextLease(lease) == IF lease = MaxLease THEN 1 ELSE lease + 1

VARIABLES
    context,
    inputRevision,
    coordinatorLease,
    invalidating,
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
    writerDuringFadeIn,
    reachedPrepared,
    reachedBlackCommit,
    reachedBufferedRevision,
    reachedInvalidationDuringPreparation,
    reachedInvalidationDuringFade

vars == <<
    context,
    inputRevision,
    coordinatorLease,
    invalidating,
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
    writerDuringFadeIn,
    reachedPrepared,
    reachedBlackCommit,
    reachedBufferedRevision,
    reachedInvalidationDuringPreparation,
    reachedInvalidationDuringFade
>>

Init ==
    /\ context = 0
    /\ inputRevision = 0
    /\ coordinatorLease = 1
    /\ invalidating = FALSE
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
    /\ writerDuringFadeIn = FALSE
    /\ reachedPrepared = FALSE
    /\ reachedBlackCommit = FALSE
    /\ reachedBufferedRevision = FALSE
    /\ reachedInvalidationDuringPreparation = FALSE
    /\ reachedInvalidationDuringFade = FALSE

StartPreparation ==
    /\ ~invalidating
    /\ stagePhase = "none"
    /\ stagePhase' = "preparing"
    /\ stageContext' = context
    /\ stageLease' = coordinatorLease
    /\ stageSemanticRevision' = inputRevision
    /\ stageProjectedRevision' = NoValue
    /\ bufferedRevision' = NoValue
    /\ UNCHANGED <<
        context,
        inputRevision,
        coordinatorLease,
        invalidating,
        visibleContext,
        visibleLease,
        visibleSemanticRevision,
        visibleProjectedRevision,
        invalidatedCommit,
        mismatchedCommit,
        writerDuringFadeIn,
        reachedPrepared,
        reachedBlackCommit,
        reachedBufferedRevision,
        reachedInvalidationDuringPreparation,
        reachedInvalidationDuringFade
        >>

CompleteWorker ==
    /\ stagePhase = "preparing"
    /\ ~invalidating
    /\ stageContext = context
    /\ stagePhase' = "prepared"
    /\ stageProjectedRevision' = stageSemanticRevision
    /\ reachedPrepared' = TRUE
    /\ UNCHANGED <<
        context,
        inputRevision,
        coordinatorLease,
        invalidating,
        stageContext,
        stageLease,
        stageSemanticRevision,
        bufferedRevision,
        visibleContext,
        visibleLease,
        visibleSemanticRevision,
        visibleProjectedRevision,
        invalidatedCommit,
        mismatchedCommit,
        writerDuringFadeIn,
        reachedBlackCommit,
        reachedBufferedRevision,
        reachedInvalidationDuringPreparation,
        reachedInvalidationDuringFade
        >>

CompleteStaleWorker ==
    /\ Implementation = "brokenContext"
    /\ stagePhase = "preparing"
    /\ invalidating \/ stageContext # context
    /\ stagePhase' = "prepared"
    /\ stageProjectedRevision' = stageSemanticRevision
    /\ reachedPrepared' = TRUE
    /\ UNCHANGED <<
        context,
        inputRevision,
        coordinatorLease,
        invalidating,
        stageContext,
        stageLease,
        stageSemanticRevision,
        bufferedRevision,
        visibleContext,
        visibleLease,
        visibleSemanticRevision,
        visibleProjectedRevision,
        invalidatedCommit,
        mismatchedCommit,
        writerDuringFadeIn,
        reachedBlackCommit,
        reachedBufferedRevision,
        reachedInvalidationDuringPreparation,
        reachedInvalidationDuringFade
        >>

BeginPreparedReport ==
    /\ stagePhase = "prepared"
    /\ stagePhase' = "reporting"
    /\ UNCHANGED <<
        context,
        inputRevision,
        coordinatorLease,
        invalidating,
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
        writerDuringFadeIn,
        reachedPrepared,
        reachedBlackCommit,
        reachedBufferedRevision,
        reachedInvalidationDuringPreparation,
        reachedInvalidationDuringFade
        >>

AcceptPreparedReport ==
    /\ stagePhase = "reporting"
    /\ ~invalidating
    /\ stageContext = context
    /\ stagePhase' = "reported"
    /\ UNCHANGED <<
        context,
        inputRevision,
        coordinatorLease,
        invalidating,
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
        writerDuringFadeIn,
        reachedPrepared,
        reachedBlackCommit,
        reachedBufferedRevision,
        reachedInvalidationDuringPreparation,
        reachedInvalidationDuringFade
        >>

AcceptStalePreparedReport ==
    /\ Implementation = "brokenContext"
    /\ stagePhase = "reporting"
    /\ invalidating \/ stageContext # context
    /\ stagePhase' = "reported"
    /\ UNCHANGED <<
        context,
        inputRevision,
        coordinatorLease,
        invalidating,
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
        writerDuringFadeIn,
        reachedPrepared,
        reachedBlackCommit,
        reachedBufferedRevision,
        reachedInvalidationDuringPreparation,
        reachedInvalidationDuringFade
        >>

RejectStalePreparedReport ==
    /\ Implementation # "brokenContext"
    /\ stagePhase = "reporting"
    /\ invalidating \/ stageContext # context
    /\ stagePhase' = "none"
    /\ stageContext' = NoValue
    /\ stageLease' = NoLease
    /\ stageSemanticRevision' = NoValue
    /\ stageProjectedRevision' = NoValue
    /\ bufferedRevision' = NoValue
    /\ UNCHANGED <<
        context,
        inputRevision,
        coordinatorLease,
        invalidating,
        visibleContext,
        visibleLease,
        visibleSemanticRevision,
        visibleProjectedRevision,
        invalidatedCommit,
        mismatchedCommit,
        writerDuringFadeIn,
        reachedPrepared,
        reachedBlackCommit,
        reachedBufferedRevision,
        reachedInvalidationDuringPreparation,
        reachedInvalidationDuringFade
        >>

BeginFadeOut ==
    /\ stagePhase = "reported"
    /\ stagePhase' = "fadingOut"
    /\ UNCHANGED <<
        context,
        inputRevision,
        coordinatorLease,
        invalidating,
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
        writerDuringFadeIn,
        reachedPrepared,
        reachedBlackCommit,
        reachedBufferedRevision,
        reachedInvalidationDuringPreparation,
        reachedInvalidationDuringFade
        >>

BeginCoordinatorCommit ==
    /\ stagePhase = "fadingOut"
    /\ stagePhase' = "committing"
    /\ UNCHANGED <<
        context,
        inputRevision,
        coordinatorLease,
        invalidating,
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
        writerDuringFadeIn,
        reachedPrepared,
        reachedBlackCommit,
        reachedBufferedRevision,
        reachedInvalidationDuringPreparation,
        reachedInvalidationDuringFade
        >>

UpdateTargetInput ==
    /\ ~invalidating
    /\ inputRevision < MaxRevision
    /\ inputRevision' = inputRevision + 1
    /\ bufferedRevision' = IF stagePhase \in {"fadingOut", "committing", "fadingIn"}
        THEN inputRevision + 1
        ELSE bufferedRevision
    /\ reachedBufferedRevision' = (
        reachedBufferedRevision \/
        stagePhase \in {"fadingOut", "committing", "fadingIn"}
        )
    /\ UNCHANGED <<
        context,
        coordinatorLease,
        invalidating,
        stagePhase,
        stageContext,
        stageLease,
        stageSemanticRevision,
        stageProjectedRevision,
        visibleContext,
        visibleLease,
        visibleSemanticRevision,
        visibleProjectedRevision,
        invalidatedCommit,
        mismatchedCommit,
        writerDuringFadeIn,
        reachedPrepared,
        reachedBlackCommit,
        reachedInvalidationDuringPreparation,
        reachedInvalidationDuringFade
        >>

InvalidateProjectionContext ==
    /\ ~invalidating
    /\ context < MaxContext
    /\ context' = context + 1
    /\ inputRevision' = 0
    /\ invalidating' = TRUE
    /\ reachedInvalidationDuringPreparation' = (
        reachedInvalidationDuringPreparation \/
        stagePhase \in {"preparing", "prepared", "reporting", "reported"}
        )
    /\ reachedInvalidationDuringFade' = (
        reachedInvalidationDuringFade \/
        stagePhase \in {"fadingOut", "committing", "fadingIn"}
        )
    /\ IF Implementation = "brokenContext"
        THEN UNCHANGED <<
            stagePhase,
            stageContext,
            stageLease,
            stageSemanticRevision,
            stageProjectedRevision,
            bufferedRevision
        >>
        ELSE /\ stagePhase' = "none"
             /\ stageContext' = NoValue
             /\ stageLease' = NoLease
             /\ stageSemanticRevision' = NoValue
             /\ stageProjectedRevision' = NoValue
             /\ bufferedRevision' = NoValue
    /\ UNCHANGED <<
        coordinatorLease,
        visibleContext,
        visibleLease,
        visibleSemanticRevision,
        visibleProjectedRevision,
        invalidatedCommit,
        mismatchedCommit,
        writerDuringFadeIn,
        reachedPrepared,
        reachedBlackCommit,
        reachedBufferedRevision
        >>

CommitCurrentPreparedPair ==
    /\ Implementation # "brokenPair"
    /\ stagePhase = "committing"
    /\ ~invalidating
    /\ stageContext = context
    /\ stageLease = coordinatorLease
    /\ stagePhase' = "fadingIn"
    /\ visibleContext' = stageContext
    /\ visibleLease' = stageLease
    /\ visibleSemanticRevision' = stageSemanticRevision
    /\ visibleProjectedRevision' = stageProjectedRevision
    /\ reachedBlackCommit' = TRUE
    /\ UNCHANGED <<
        context,
        inputRevision,
        coordinatorLease,
        invalidating,
        stageContext,
        stageLease,
        stageSemanticRevision,
        stageProjectedRevision,
        bufferedRevision,
        invalidatedCommit,
        mismatchedCommit,
        writerDuringFadeIn,
        reachedPrepared,
        reachedBufferedRevision,
        reachedInvalidationDuringPreparation,
        reachedInvalidationDuringFade
        >>

CommitBrokenPair ==
    /\ Implementation = "brokenPair"
    /\ stagePhase = "committing"
    /\ ~invalidating
    /\ stageContext = context
    /\ stageLease = coordinatorLease
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
        context,
        inputRevision,
        coordinatorLease,
        invalidating,
        stageContext,
        stageLease,
        stageSemanticRevision,
        stageProjectedRevision,
        bufferedRevision,
        invalidatedCommit,
        writerDuringFadeIn,
        reachedPrepared,
        reachedBufferedRevision,
        reachedInvalidationDuringPreparation,
        reachedInvalidationDuringFade
        >>

CommitBrokenContext ==
    /\ Implementation = "brokenContext"
    /\ stagePhase = "committing"
    /\ invalidating \/ stageContext # context \/ stageLease # coordinatorLease
    /\ stagePhase' = "fadingIn"
    /\ visibleContext' = stageContext
    /\ visibleLease' = stageLease
    /\ visibleSemanticRevision' = stageSemanticRevision
    /\ visibleProjectedRevision' = stageProjectedRevision
    /\ invalidatedCommit' = TRUE
    /\ reachedBlackCommit' = TRUE
    /\ UNCHANGED <<
        context,
        inputRevision,
        coordinatorLease,
        invalidating,
        stageContext,
        stageLease,
        stageSemanticRevision,
        stageProjectedRevision,
        bufferedRevision,
        mismatchedCommit,
        writerDuringFadeIn,
        reachedPrepared,
        reachedBufferedRevision,
        reachedInvalidationDuringPreparation,
        reachedInvalidationDuringFade
        >>

RejectInvalidatedCommit ==
    /\ Implementation # "brokenContext"
    /\ stagePhase = "committing"
    /\ invalidating \/ stageContext # context \/ stageLease # coordinatorLease
    /\ stagePhase' = "none"
    /\ stageContext' = NoValue
    /\ stageLease' = NoLease
    /\ stageSemanticRevision' = NoValue
    /\ stageProjectedRevision' = NoValue
    /\ bufferedRevision' = NoValue
    /\ UNCHANGED <<
        context,
        inputRevision,
        coordinatorLease,
        invalidating,
        visibleContext,
        visibleLease,
        visibleSemanticRevision,
        visibleProjectedRevision,
        invalidatedCommit,
        mismatchedCommit,
        writerDuringFadeIn,
        reachedPrepared,
        reachedBlackCommit,
        reachedBufferedRevision,
        reachedInvalidationDuringPreparation,
        reachedInvalidationDuringFade
        >>

PublishDuringFadeIn ==
    /\ Implementation = "brokenWriter"
    /\ stagePhase = "fadingIn"
    /\ bufferedRevision # NoValue
    /\ visibleContext' = context
    /\ visibleLease' = coordinatorLease
    /\ visibleSemanticRevision' = bufferedRevision
    /\ visibleProjectedRevision' = bufferedRevision
    /\ bufferedRevision' = NoValue
    /\ writerDuringFadeIn' = TRUE
    /\ UNCHANGED <<
        context,
        inputRevision,
        coordinatorLease,
        invalidating,
        stagePhase,
        stageContext,
        stageLease,
        stageSemanticRevision,
        stageProjectedRevision,
        invalidatedCommit,
        mismatchedCommit,
        reachedPrepared,
        reachedBlackCommit,
        reachedBufferedRevision,
        reachedInvalidationDuringPreparation,
        reachedInvalidationDuringFade
        >>

CompleteFadeIn ==
    /\ stagePhase = "fadingIn"
    /\ stagePhase' = "none"
    /\ stageContext' = NoValue
    /\ stageLease' = NoLease
    /\ stageSemanticRevision' = NoValue
    /\ stageProjectedRevision' = NoValue
    /\ visibleSemanticRevision' = IF bufferedRevision = NoValue
        THEN visibleSemanticRevision
        ELSE bufferedRevision
    /\ visibleProjectedRevision' = IF bufferedRevision = NoValue
        THEN visibleProjectedRevision
        ELSE bufferedRevision
    /\ bufferedRevision' = NoValue
    /\ UNCHANGED <<
        context,
        inputRevision,
        coordinatorLease,
        invalidating,
        visibleContext,
        visibleLease,
        invalidatedCommit,
        mismatchedCommit,
        writerDuringFadeIn,
        reachedPrepared,
        reachedBlackCommit,
        reachedBufferedRevision,
        reachedInvalidationDuringPreparation,
        reachedInvalidationDuringFade
        >>

FinishInvalidation ==
    /\ invalidating
    /\ invalidating' = FALSE
    /\ coordinatorLease' = NextLease(coordinatorLease)
    /\ stagePhase' = "none"
    /\ stageContext' = NoValue
    /\ stageLease' = NoLease
    /\ stageSemanticRevision' = NoValue
    /\ stageProjectedRevision' = NoValue
    /\ bufferedRevision' = NoValue
    /\ visibleContext' = context
    /\ visibleLease' = NoLease
    /\ visibleSemanticRevision' = inputRevision
    /\ visibleProjectedRevision' = inputRevision
    /\ UNCHANGED <<
        context,
        inputRevision,
        invalidatedCommit,
        mismatchedCommit,
        writerDuringFadeIn,
        reachedPrepared,
        reachedBlackCommit,
        reachedBufferedRevision,
        reachedInvalidationDuringPreparation,
        reachedInvalidationDuringFade
        >>

Next ==
    \/ StartPreparation
    \/ CompleteWorker
    \/ CompleteStaleWorker
    \/ BeginPreparedReport
    \/ AcceptPreparedReport
    \/ AcceptStalePreparedReport
    \/ RejectStalePreparedReport
    \/ BeginFadeOut
    \/ BeginCoordinatorCommit
    \/ UpdateTargetInput
    \/ InvalidateProjectionContext
    \/ CommitCurrentPreparedPair
    \/ CommitBrokenPair
    \/ CommitBrokenContext
    \/ RejectInvalidatedCommit
    \/ PublishDuringFadeIn
    \/ CompleteFadeIn
    \/ FinishInvalidation

Spec == Init /\ [][Next]_vars

TypeOK ==
    /\ context \in Contexts
    /\ inputRevision \in Revisions
    /\ coordinatorLease \in Leases
    /\ invalidating \in BOOLEAN
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
    /\ writerDuringFadeIn \in BOOLEAN
    /\ reachedPrepared \in BOOLEAN
    /\ reachedBlackCommit \in BOOLEAN
    /\ reachedBufferedRevision \in BOOLEAN
    /\ reachedInvalidationDuringPreparation \in BOOLEAN
    /\ reachedInvalidationDuringFade \in BOOLEAN

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

ExactVisiblePair ==
    visibleSemanticRevision = visibleProjectedRevision

NoInvalidatedContextCommit ==
    ~invalidatedCommit

NoMismatchedCommit ==
    ~mismatchedCommit

NoWriterDuringFadeIn ==
    ~writerDuringFadeIn

RequiredPathsNotAllReached ==
    ~(reachedPrepared /\
      reachedBlackCommit /\
      reachedBufferedRevision /\
      reachedInvalidationDuringPreparation /\
      reachedInvalidationDuringFade)

====
