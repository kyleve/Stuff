---- MODULE PollingPublication ----
EXTENDS Integers, Sequences

CONSTANTS Implementation, Operations, FinalDeactivate

AllowedImplementations == {"current", "leaseLess", "revisionLess"}
AllowedOperations == {"activate", "update"}

ASSUME /\ Implementation \in AllowedImplementations
       /\ Operations \in Seq(AllowedOperations)
       /\ Len(Operations) > 0
       /\ FinalDeactivate \in BOOLEAN

ContextCount == Len(Operations) + 1
Contexts == 1..ContextCount
Tokens == Contexts
Revisions == 0..2

NoUpdate == [
    kind |-> "none",
    token |-> 0,
    context |-> 0,
    revision |-> 0,
    state |-> "none"
]

InactiveUpdate == [
    kind |-> "inactive",
    token |-> 0,
    context |-> 0,
    revision |-> 0,
    state |-> "inactive"
]

ActiveUpdate(token, revision, state) == [
    kind |-> "active",
    token |-> token,
    context |-> token,
    revision |-> revision,
    state |-> state
]

ActiveUpdates ==
    {ActiveUpdate(token, 1, "loading") : token \in Tokens} \union
    {ActiveUpdate(token, 2, "healthy") : token \in Tokens}

Updates == {NoUpdate, InactiveUpdate} \union ActiveUpdates

InactiveAcceptance(applied) == [
    kind |-> "inactive",
    token |-> 0,
    revision |-> 0,
    inactiveApplied |-> applied
]

AwaitingAcceptance == [
    kind |-> "awaiting",
    token |-> 0,
    revision |-> 0,
    inactiveApplied |-> FALSE
]

ActiveAcceptance(token, revision) == [
    kind |-> "active",
    token |-> token,
    revision |-> revision,
    inactiveApplied |-> FALSE
]

AcceptanceStates ==
    {InactiveAcceptance(applied) : applied \in BOOLEAN} \union
    {AwaitingAcceptance} \union
    {ActiveAcceptance(token, revision) :
        token \in Tokens, revision \in Revisions}

SourcePhases == {"dormant", "ready", "done"}
LifecyclePhases == {
    "stable", "resetting", "callingCore", "callingUpdate", "tokenMinted", "draining", "returningToken",
    "installingToken", "readingCurrent", "recoveryHeld", "deactivating",
    "deactivationDrain", "resettingInactive", "done"
}

MaxGeneration == 4 * ContextCount + 4

Frame(token, context, revision, generation) == [
    token |-> token,
    context |-> context,
    revision |-> revision,
    generation |-> generation
]

Frames == [
    token : Tokens,
    context : Contexts,
    revision : 1..2,
    generation : 0..MaxGeneration
]

OneActivation == <<"activate">>
OneUpdate == <<"update">>
ActivationThenUpdate == <<"activate", "update">>

(* --algorithm PollingPublicationAlgorithm {
variables operationIndex = 0,
          lifecyclePhase = "stable",
          targetContext = 1,
          mintedToken = 1,
          coreToken = 1,
          coreContext = 1,
          coreRevision = 1,
          coreUpdate = ActiveUpdate(1, 1, "loading"),
          sourcePhase = [token \in Tokens |->
              IF token = 1 THEN "ready" ELSE "dormant"],
          streamBuffer = ActiveUpdate(1, 1, "loading"),
          streamDelivery = NoUpdate,
          recoveryUpdate = NoUpdate,
          acceptance = ActiveAcceptance(1, 1),
          lastConsumed = ActiveUpdate(1, 1, "loading"),
          stateGeneration = 1,
          pendingFrames = {},
          uiState = "loading",
          contentContext = 0,
          contentToken = 0,
          contentRevision = 0,
          revisionOrderPreserved = TRUE,
          finished = FALSE,
          sawOldBufferedOrInFlight = FALSE,
          sawOldUpdateRejected = FALSE,
          sawEarlyNewUpdateRejected = FALSE,
          sawRecoveryApplied = FALSE,
          sawOvertakenRecoveryRejected = FALSE,
          sawStaleFrameRejected = FALSE,
          sawInactiveApplied = FALSE,
          sawUpdateOperation = FALSE;

define {
    IsActiveUpdate(update) == update.kind = "active"

    IsOldForTarget(update) ==
        /\ IsActiveUpdate(update)
        /\ update.context /= targetContext

    AcceptsActive(update) ==
        /\ IsActiveUpdate(update)
        /\ CASE Implementation = "leaseLess" -> targetContext /= 0
              [] Implementation = "revisionLess" ->
                    /\ acceptance.kind = "active"
                    /\ update.token = acceptance.token
                    /\ update /= lastConsumed
              [] Implementation = "current" ->
                    /\ acceptance.kind = "active"
                    /\ update.token = acceptance.token
                    /\ update.revision > acceptance.revision

    AcceptsInactive(update) ==
        /\ update = InactiveUpdate
        /\ CASE Implementation = "current" ->
                    /\ acceptance.kind = "inactive"
                    /\ ~acceptance.inactiveApplied
              [] Implementation \in {"leaseLess", "revisionLess"} ->
                    /\ targetContext = 0
                    /\ update /= lastConsumed

    Quiescent ==
        /\ finished
        /\ lifecyclePhase = "done"
        /\ streamBuffer = NoUpdate
        /\ streamDelivery = NoUpdate
        /\ recoveryUpdate = NoUpdate
        /\ pendingFrames = {}
        /\ \A token \in Tokens : sourcePhase[token] /= "ready"

    CorrectlySettled ==
        /\ Quiescent
        /\ IF FinalDeactivate
              THEN /\ targetContext = 0
                   /\ coreToken = 0
                   /\ coreContext = 0
                   /\ coreRevision = 0
                   /\ coreUpdate = InactiveUpdate
                   /\ acceptance.kind = "inactive"
                   /\ uiState = "inactive"
                   /\ contentContext = 0
                   /\ contentToken = 0
                   /\ contentRevision = 0
              ELSE /\ targetContext = ContextCount
                   /\ coreToken = ContextCount
                   /\ coreContext = ContextCount
                   /\ coreRevision = 2
                   /\ coreUpdate = ActiveUpdate(ContextCount, 2, "healthy")
                   /\ acceptance = ActiveAcceptance(ContextCount, 2)
                   /\ uiState = "healthy"
                   /\ contentContext = ContextCount
                   /\ contentToken = ContextCount
                   /\ contentRevision = 2
}

fair process (Lifecycle = <<"Lifecycle", 0>>) {
BeginNextOperation:
    while (operationIndex < Len(Operations)) {
        with (nextContext = operationIndex + 2) {
            targetContext := nextContext ||
            lifecyclePhase := "resetting" ||
            acceptance := AwaitingAcceptance ||
            lastConsumed := NoUpdate ||
            stateGeneration := stateGeneration + 1 ||
            uiState := "loading" ||
            contentContext := 0 ||
            contentToken := 0 ||
            contentRevision := 0 ||
            sawOldBufferedOrInFlight :=
                sawOldBufferedOrInFlight \/
                (IsActiveUpdate(streamBuffer) /\
                 streamBuffer.context /= nextContext) \/
                (IsActiveUpdate(streamDelivery) /\
                 streamDelivery.context /= nextContext);
        };

ResetOrQueryBoundary:
        \* An activation awaits flightsRuntime.reset(). A query-only update
        \* skips that call, but still crosses into the coordinator actor.
        lifecyclePhase := IF Operations[operationIndex + 1] = "activate"
            THEN "callingCore" ELSE "callingUpdate" ||
        sawUpdateOperation := sawUpdateOperation \/
            (Operations[operationIndex + 1] = "update");

CoordinatorMintsToken:
        \* activate(...) and update(...) mint before their queued operation runs.
        mintedToken := operationIndex + 2 ||
        lifecyclePhase := "tokenMinted";

CoreBeginReplacement:
        with (oldToken = coreToken) {
            coreToken := 0 ||
            coreContext := 0 ||
            coreRevision := 0 ||
            coreUpdate := InactiveUpdate ||
            streamBuffer := InactiveUpdate ||
            lifecyclePhase := "draining" ||
            sourcePhase := IF oldToken = 0
                THEN sourcePhase
                ELSE [sourcePhase EXCEPT ![oldToken] = "done"];
        };

CoreDrainOldPoller:
        \* replace(...) is suspended at await oldTask.value here.
        with (newToken = mintedToken) {
            coreToken := newToken ||
            coreContext := newToken ||
            coreRevision := 1 ||
            coreUpdate := ActiveUpdate(newToken, 1, "loading") ||
            sourcePhase := [sourcePhase EXCEPT ![newToken] = "ready"] ||
            streamBuffer := ActiveUpdate(newToken, 1, "loading") ||
            lifecyclePhase := "returningToken";
        };

CoordinatorReturnsToken:
        \* The runtime resumes after await pollingCoordinator.activate/update.
        lifecyclePhase := "installingToken";

InstallExpectedToken:
        with (newToken = mintedToken) {
            acceptance := ActiveAcceptance(newToken, 0) ||
            lifecyclePhase := "readingCurrent";
        };

CaptureCurrentUpdate:
        \* currentUpdate() captures Core state before the caller actor resumes.
        recoveryUpdate := coreUpdate ||
        lifecyclePhase := "recoveryHeld";

ApplyCurrentUpdate:
        if (AcceptsActive(recoveryUpdate)) {
            with (newGeneration = stateGeneration + 1) {
                revisionOrderPreserved :=
                    revisionOrderPreserved /\
                    (acceptance.kind /= "active" \/
                     recoveryUpdate.token /= acceptance.token \/
                     recoveryUpdate.revision > acceptance.revision) ||
                acceptance := IF Implementation = "leaseLess"
                    THEN acceptance
                    ELSE ActiveAcceptance(
                        recoveryUpdate.token,
                        recoveryUpdate.revision) ||
                lastConsumed := recoveryUpdate ||
                stateGeneration := newGeneration ||
                pendingFrames := IF recoveryUpdate.state = "healthy"
                    THEN pendingFrames \union {
                        Frame(
                            recoveryUpdate.token,
                            recoveryUpdate.context,
                            recoveryUpdate.revision,
                            newGeneration)
                    }
                    ELSE pendingFrames ||
                uiState := IF recoveryUpdate.state = "loading"
                    THEN "loading" ELSE uiState ||
                sawRecoveryApplied := TRUE;
            };
        } else {
            sawOldUpdateRejected :=
                sawOldUpdateRejected \/ IsOldForTarget(recoveryUpdate) ||
            sawEarlyNewUpdateRejected :=
                sawEarlyNewUpdateRejected \/
                (IsActiveUpdate(recoveryUpdate) /\
                 recoveryUpdate.context = targetContext /\
                 acceptance.kind = "awaiting") ||
            sawOvertakenRecoveryRejected :=
                sawOvertakenRecoveryRejected \/
                (Implementation = "current" /\
                 IsActiveUpdate(recoveryUpdate) /\
                 acceptance.kind = "active" /\
                 recoveryUpdate.token = acceptance.token /\
                 recoveryUpdate.revision < acceptance.revision);
        };
        recoveryUpdate := NoUpdate ||
        operationIndex := operationIndex + 1 ||
        lifecyclePhase := "stable";
    };

BeginFinalDeactivation:
    if (FinalDeactivate) {
        targetContext := 0 ||
        lifecyclePhase := "deactivating" ||
        acceptance := InactiveAcceptance(FALSE) ||
        lastConsumed := NoUpdate ||
        stateGeneration := stateGeneration + 1 ||
        contentContext := 0 ||
        contentToken := 0 ||
        contentRevision := 0;

CoreBeginDeactivation:
        with (oldToken = coreToken) {
            coreToken := 0 ||
            coreContext := 0 ||
            coreRevision := 0 ||
            coreUpdate := InactiveUpdate ||
            streamBuffer := InactiveUpdate ||
            lifecyclePhase := "deactivationDrain" ||
            sourcePhase := IF oldToken = 0
                THEN sourcePhase
                ELSE [sourcePhase EXCEPT ![oldToken] = "done"];
        };

CoreDrainForDeactivation:
        \* performDeactivate(...) publishes inactive again after the drain.
        coreUpdate := InactiveUpdate ||
        streamBuffer := InactiveUpdate ||
        lifecyclePhase := "resettingInactive";

FinishDeactivation:
        \* The runtime resumes after flightsRuntime.reset().
        uiState := "inactive" ||
        finished := TRUE ||
        lifecyclePhase := "done";
    } else {
        finished := TRUE ||
        lifecyclePhase := "done";
    };

LifecycleDone:
    while (TRUE) {
        await Quiescent;
        skip;
    }
}

fair process (Source \in {<<"Source", token>> : token \in Tokens}) {
PublishHealthySnapshot:
    while (TRUE) {
        await sourcePhase[self[2]] = "ready" /\ coreToken = self[2];
        coreRevision := 2 ||
        coreUpdate := ActiveUpdate(self[2], 2, "healthy") ||
        streamBuffer := ActiveUpdate(self[2], 2, "healthy") ||
        sourcePhase := [sourcePhase EXCEPT ![self[2]] = "done"];
    }
}

fair process (Observer = <<"Observer", 0>>) {
TakeBufferedUpdate:
    while (TRUE) {
        await streamDelivery = NoUpdate /\ streamBuffer /= NoUpdate;
        streamDelivery := streamBuffer ||
        streamBuffer := NoUpdate;

ApplyStreamUpdate:
        if (AcceptsActive(streamDelivery)) {
            with (newGeneration = stateGeneration + 1) {
                revisionOrderPreserved :=
                    revisionOrderPreserved /\
                    (acceptance.kind /= "active" \/
                     streamDelivery.token /= acceptance.token \/
                     streamDelivery.revision > acceptance.revision) ||
                acceptance := IF Implementation = "leaseLess"
                    THEN acceptance
                    ELSE ActiveAcceptance(
                        streamDelivery.token,
                        streamDelivery.revision) ||
                lastConsumed := streamDelivery ||
                stateGeneration := newGeneration ||
                pendingFrames := IF streamDelivery.state = "healthy"
                    THEN pendingFrames \union {
                        Frame(
                            streamDelivery.token,
                            streamDelivery.context,
                            streamDelivery.revision,
                            newGeneration)
                    }
                    ELSE pendingFrames ||
                uiState := IF streamDelivery.state = "loading"
                    THEN "loading" ELSE uiState;
            };
        } else if (AcceptsInactive(streamDelivery)) {
            acceptance := IF Implementation = "current"
                THEN InactiveAcceptance(TRUE)
                ELSE acceptance ||
            lastConsumed := streamDelivery ||
            stateGeneration := stateGeneration + 1 ||
            uiState := "inactive" ||
            contentContext := 0 ||
            contentToken := 0 ||
            contentRevision := 0 ||
            sawInactiveApplied := TRUE;
        } else {
            sawOldUpdateRejected :=
                sawOldUpdateRejected \/ IsOldForTarget(streamDelivery) ||
            sawEarlyNewUpdateRejected :=
                sawEarlyNewUpdateRejected \/
                (IsActiveUpdate(streamDelivery) /\
                 streamDelivery.context = targetContext /\
                 acceptance.kind = "awaiting");
        };
        streamDelivery := NoUpdate;
    }
}

fair process (FrameWorker = <<"FrameWorker", 0>>) {
CompleteFrame:
    while (TRUE) {
        await pendingFrames /= {};
        with (frame \in pendingFrames) {
            pendingFrames := pendingFrames \ {frame};
            if (frame.generation = stateGeneration) {
                uiState := "healthy" ||
                contentContext := frame.context ||
                contentToken := frame.token ||
                contentRevision := frame.revision;
            } else {
                sawStaleFrameRejected := TRUE;
            };
        };
    }
}
} *)

TypeOK ==
    /\ operationIndex \in 0..Len(Operations)
    /\ lifecyclePhase \in LifecyclePhases
    /\ targetContext \in 0..ContextCount
    /\ mintedToken \in Tokens
    /\ coreToken \in 0..ContextCount
    /\ coreContext \in 0..ContextCount
    /\ coreRevision \in Revisions
    /\ coreUpdate \in Updates
    /\ sourcePhase \in [Tokens -> SourcePhases]
    /\ streamBuffer \in Updates
    /\ streamDelivery \in Updates
    /\ recoveryUpdate \in Updates
    /\ acceptance \in AcceptanceStates
    /\ lastConsumed \in Updates
    /\ stateGeneration \in 0..MaxGeneration
    /\ pendingFrames \subseteq Frames
    /\ uiState \in {"inactive", "loading", "healthy"}
    /\ contentContext \in 0..ContextCount
    /\ contentToken \in 0..ContextCount
    /\ contentRevision \in Revisions
    /\ revisionOrderPreserved \in BOOLEAN
    /\ finished \in BOOLEAN
    /\ sawOldBufferedOrInFlight \in BOOLEAN
    /\ sawOldUpdateRejected \in BOOLEAN
    /\ sawEarlyNewUpdateRejected \in BOOLEAN
    /\ sawRecoveryApplied \in BOOLEAN
    /\ sawOvertakenRecoveryRejected \in BOOLEAN
    /\ sawStaleFrameRejected \in BOOLEAN
    /\ sawInactiveApplied \in BOOLEAN
    /\ sawUpdateOperation \in BOOLEAN

AcceptanceShape ==
    /\ (acceptance.kind = "active" =>
            /\ acceptance.token \in Tokens
            /\ acceptance.revision \in Revisions
            /\ acceptance.token = targetContext)
    /\ (acceptance.kind /= "active" =>
            /\ acceptance.token = 0
            /\ acceptance.revision = 0)

CorePublicationShape ==
    /\ (coreToken = 0 =>
            /\ coreContext = 0
            /\ coreRevision = 0
            /\ coreUpdate = InactiveUpdate)
    /\ (coreToken /= 0 =>
            /\ coreContext = coreToken
            /\ coreRevision \in 1..2
            /\ coreUpdate = ActiveUpdate(
                coreToken,
                coreRevision,
                IF coreRevision = 1 THEN "loading" ELSE "healthy"))

ExactTokenAcceptanceSafety ==
    lastConsumed.kind = "active" =>
        /\ targetContext /= 0
        /\ lastConsumed.token = targetContext
        /\ lastConsumed.context = targetContext

ExactTokenPublicationSafety ==
    /\ (lastConsumed.kind = "active" /\ lastConsumed.state = "healthy" =>
            /\ targetContext /= 0
            /\ lastConsumed.token = targetContext
            /\ lastConsumed.context = targetContext)
    /\ (contentContext /= 0 =>
            /\ targetContext /= 0
            /\ contentToken = targetContext
            /\ contentContext = targetContext)

AcceptedRevisionsNeverRegress == revisionOrderPreserved

CorrectAtQuiescence == Quiescent => CorrectlySettled

EventuallyConverges == finished ~> CorrectlySettled

OldBufferedOrInFlightNotReached == ~sawOldBufferedOrInFlight
OldUpdateRejectionNotReached == ~sawOldUpdateRejected
EarlyNewUpdateRejectionNotReached == ~sawEarlyNewUpdateRejected
RecoveryApplicationNotReached == ~sawRecoveryApplied
OvertakenRecoveryRejectionNotReached == ~sawOvertakenRecoveryRejected
StaleFrameRejectionNotReached == ~sawStaleFrameRejected
InactiveApplicationNotReached == ~sawInactiveApplied
UpdateOperationNotReached == ~sawUpdateOperation

====
