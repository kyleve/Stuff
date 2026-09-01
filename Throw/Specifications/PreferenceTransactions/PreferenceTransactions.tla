---- MODULE PreferenceTransactions ----
EXTENDS Integers, Sequences, FiniteSets

CONSTANTS Implementation, MutationKinds, MaxForegroundEdits

ASSUME /\ Implementation \in {"current", "brokenRetry", "brokenObserver"}
       /\ MutationKinds \subseteq {"source", "location"}
       /\ MutationKinds # {}
       /\ MaxForegroundEdits \in 0..2
       /\ (Implementation = "brokenRetry" => MutationKinds = {"source"})
       /\ (Implementation = "brokenObserver" => MutationKinds = {"location"})

Sources == {0, 1}
Observers == {0, 1}
EditRevisions == 0..MaxForegroundEdits
CredentialIDs == {1}

PreferenceValues == [
    source: Sources,
    observer: Observers,
    edit: EditRevisions
]

InitialPreferences == [source |-> 0, observer |-> 0, edit |-> 0]

MutatedPreferences(preferences, kind) ==
    [source |-> IF kind = "source" THEN 1 ELSE preferences.source,
     observer |-> IF kind = "location" THEN 1 ELSE preferences.observer,
     edit |-> preferences.edit]

Phases == {
    "selecting",
    "waitingInitialWorker",
    "validatingSource",
    "waitingCredentialRead",
    "waitingCredentialSave",
    "brokenEarlyPublication",
    "buildingCandidate",
    "waitingPreferenceResult",
    "waitingRuntimeDeactivation",
    "waitingProjectionWorkerReset",
    "waitingCoordinatorConfigure",
    "waitingCoordinatorState",
    "waitingDiscardFade",
    "waitingDiscardWorkerReset",
    "completingInvalidation",
    "restoringCredential",
    "finishing",
    "done"
}

AwaitPhases == {
    "waitingInitialWorker",
    "waitingCredentialRead",
    "waitingCredentialSave",
    "waitingPreferenceResult",
    "waitingRuntimeDeactivation",
    "waitingProjectionWorkerReset",
    "waitingCoordinatorConfigure",
    "waitingCoordinatorState",
    "waitingDiscardFade",
    "waitingDiscardWorkerReset",
    "restoringCredential"
}

Outcomes == {"none", "success", "failure"}
RequestKinds == {"none", "mutation", "foreground"}
WorkerPhases == {"initialBusy", "idle", "saving"}
PublicationStates == {"notPublished", "publishedBeforeSave", "published"}
ActivationStates == {"none", "preparing", "active"}
RenderStates == {"idle", "rendering"}

(* --algorithm PreferenceTransactionsAlgorithm {
variables mutationKind = "none",
          mutationPhase = "selecting",
          livePreferences = InitialPreferences,
          durablePreferences = InitialPreferences,
          credentials = {},
          credentialMutationAttempted = FALSE,
          candidateBase = InitialPreferences,
          candidatePreferences = InitialPreferences,
          committedCandidate = InitialPreferences,
          commitKnown = FALSE,
          pendingOutcome = "none",
          reportedOutcome = "none",
          foregroundEditCount = 0,
          foregroundEditQueued = FALSE,
          deferredSaveNeeded = FALSE,
          queuedForegroundSnapshot = InitialPreferences,
          requestKind = "none",
          requestPreferences = InitialPreferences,
          requestResult = "none",
          workerPhase = "initialBusy",
          workerKind = "none",
          workerPreferences = InitialPreferences,
          saveAttempts = 0,
          publicationState = "notPublished",
          invalidationActive = FALSE,
          contextGeneration = 0,
          observerGeneration = 0,
          publishedObserverGeneration = 0,
          activationState = "active",
          activationContextGeneration = 0,
          activationObserverGeneration = 0,
          activationObserver = 0,
          preparedActivationContextGeneration = 0,
          preparedActivationObserverGeneration = 0,
          preparedActivationObserver = 0,
          renderState = "idle",
          renderContextGeneration = 0,
          renderObserverGeneration = 0,
          renderObserver = 0,
          visibleFramePresent = TRUE,
          visibleFrameObserverGeneration = 0,
          visibleFrameObserver = 0,
          sawDrift = FALSE,
          sawCommittedRetryFailure = FALSE,
          sawRetryRecoveryQueued = FALSE,
          sawObserverEarlyPublication = FALSE,
          sawStaleRenderRejected = FALSE,
          sawStaleActivationRejected = FALSE,
          sawForegroundSaveComplete = FALSE;

define {
    NextContextGeneration == contextGeneration + 1

    NextObserverGeneration ==
        observerGeneration + IF mutationKind = "location" THEN 1 ELSE 0

    Quiescent ==
        /\ mutationPhase = "done"
        /\ requestKind = "none"
        /\ requestResult = "none"
        /\ workerPhase = "idle"
        /\ workerKind = "none"
}

fair process (Mutation = "Mutation") {
MutationStep:
    while (TRUE) {
        if (mutationPhase = "selecting") {
            with (kind \in MutationKinds) {
                mutationKind := kind ||
                mutationPhase :=
                    IF kind = "source"
                    THEN "waitingInitialWorker"
                    ELSE IF Implementation = "brokenObserver"
                         THEN "brokenEarlyPublication"
                         ELSE "buildingCandidate";
            };
        } else if (mutationPhase = "waitingInitialWorker") {
            await workerPhase # "initialBusy";
            mutationPhase := "validatingSource";
        } else if (mutationPhase = "validatingSource") {
            if (Implementation = "brokenRetry") {
                mutationPhase := "waitingCredentialRead";
            } else {
                either {
                    mutationPhase := "waitingCredentialRead";
                } or {
                    pendingOutcome := "failure" ||
                    mutationPhase := "finishing";
                };
            };
        } else if (mutationPhase = "waitingCredentialRead") {
            if (Implementation = "brokenRetry") {
                credentialMutationAttempted := TRUE ||
                mutationPhase := "waitingCredentialSave";
            } else {
                either {
                    credentialMutationAttempted := TRUE ||
                    mutationPhase := "waitingCredentialSave";
                } or {
                    pendingOutcome := "failure" ||
                    mutationPhase := "finishing";
                };
            };
        } else if (mutationPhase = "waitingCredentialSave") {
            if (Implementation = "brokenRetry") {
                credentials := credentials \cup {1} ||
                mutationPhase := "buildingCandidate";
            } else {
                either {
                    credentials := credentials \cup {1} ||
                    mutationPhase := "buildingCandidate";
                } or {
                    pendingOutcome := "failure" ||
                    mutationPhase := "restoringCredential";
                };
            };
        } else if (mutationPhase = "brokenEarlyPublication") {
            livePreferences := MutatedPreferences(livePreferences, mutationKind) ||
            contextGeneration := NextContextGeneration ||
            observerGeneration := NextObserverGeneration ||
            publishedObserverGeneration := NextObserverGeneration ||
            publicationState := "publishedBeforeSave" ||
            candidateBase := MutatedPreferences(livePreferences, mutationKind) ||
            candidatePreferences := MutatedPreferences(livePreferences, mutationKind) ||
            requestKind := "mutation" ||
            requestPreferences := MutatedPreferences(livePreferences, mutationKind) ||
            mutationPhase := "waitingPreferenceResult" ||
            sawObserverEarlyPublication := TRUE;
        } else if (mutationPhase = "buildingCandidate") {
            if (Implementation = "brokenRetry") {
                candidateBase := livePreferences ||
                candidatePreferences := MutatedPreferences(livePreferences, mutationKind) ||
                requestKind := "mutation" ||
                requestPreferences := MutatedPreferences(livePreferences, mutationKind) ||
                mutationPhase := "waitingPreferenceResult";
            } else {
                either {
                    candidateBase := livePreferences ||
                    candidatePreferences := MutatedPreferences(livePreferences, mutationKind) ||
                    requestKind := "mutation" ||
                    requestPreferences := MutatedPreferences(livePreferences, mutationKind) ||
                    mutationPhase := "waitingPreferenceResult";
                } or {
                    if (commitKnown /\ Implementation = "current") {
                        livePreferences := committedCandidate ||
                        contextGeneration := NextContextGeneration ||
                        observerGeneration := NextObserverGeneration ||
                        publishedObserverGeneration := NextObserverGeneration ||
                        activationState := "none" ||
                        activationContextGeneration := -1 ||
                        activationObserverGeneration := -1 ||
                        activationObserver := 0 ||
                        visibleFramePresent :=
                            IF mutationKind = "location" THEN FALSE ELSE visibleFramePresent ||
                        publicationState := "published" ||
                        invalidationActive := TRUE ||
                        deferredSaveNeeded := TRUE ||
                        pendingOutcome := "success" ||
                        mutationPhase := "waitingRuntimeDeactivation";
                    } else {
                        pendingOutcome := "failure" ||
                        mutationPhase :=
                            IF mutationKind = "source" /\ credentialMutationAttempted
                            THEN "restoringCredential"
                            ELSE "finishing";
                    };
                };
            };
        } else if (mutationPhase = "waitingPreferenceResult") {
            await requestResult # "none";
            if (requestResult = "success") {
                if (Implementation = "brokenObserver") {
                    requestResult := "none" ||
                    commitKnown := TRUE ||
                    committedCandidate := candidatePreferences ||
                    pendingOutcome := "success" ||
                    mutationPhase := "finishing";
                } else if (candidateBase # livePreferences) {
                    requestResult := "none" ||
                    commitKnown := TRUE ||
                    committedCandidate := candidatePreferences ||
                    sawDrift := TRUE ||
                    mutationPhase := "buildingCandidate";
                } else {
                    requestResult := "none" ||
                    commitKnown := TRUE ||
                    committedCandidate := candidatePreferences ||
                    livePreferences := candidatePreferences ||
                    contextGeneration := NextContextGeneration ||
                    observerGeneration := NextObserverGeneration ||
                    publishedObserverGeneration := NextObserverGeneration ||
                    activationState := "none" ||
                    activationContextGeneration := -1 ||
                    activationObserverGeneration := -1 ||
                    activationObserver := 0 ||
                    visibleFramePresent :=
                        IF mutationKind = "location" THEN FALSE ELSE visibleFramePresent ||
                    publicationState := "published" ||
                    invalidationActive := TRUE ||
                    foregroundEditQueued := FALSE ||
                    deferredSaveNeeded := FALSE ||
                    pendingOutcome := "success" ||
                    mutationPhase := "waitingRuntimeDeactivation";
                };
            } else if (~commitKnown) {
                requestResult := "none" ||
                pendingOutcome := "failure" ||
                mutationPhase :=
                    IF mutationKind = "source" /\ credentialMutationAttempted
                    THEN "restoringCredential"
                    ELSE "finishing";
            } else if (Implementation = "current") {
                either {
                    requestResult := "none" ||
                    livePreferences := MutatedPreferences(livePreferences, mutationKind) ||
                    contextGeneration := NextContextGeneration ||
                    observerGeneration := NextObserverGeneration ||
                    publishedObserverGeneration := NextObserverGeneration ||
                    activationState := "none" ||
                    activationContextGeneration := -1 ||
                    activationObserverGeneration := -1 ||
                    activationObserver := 0 ||
                    visibleFramePresent :=
                        IF mutationKind = "location" THEN FALSE ELSE visibleFramePresent ||
                    publicationState := "published" ||
                    invalidationActive := TRUE ||
                    deferredSaveNeeded := TRUE ||
                    pendingOutcome := "success" ||
                    mutationPhase := "waitingRuntimeDeactivation" ||
                    sawCommittedRetryFailure := TRUE;
                } or {
                    requestResult := "none" ||
                    livePreferences := committedCandidate ||
                    contextGeneration := NextContextGeneration ||
                    observerGeneration := NextObserverGeneration ||
                    publishedObserverGeneration := NextObserverGeneration ||
                    activationState := "none" ||
                    activationContextGeneration := -1 ||
                    activationObserverGeneration := -1 ||
                    activationObserver := 0 ||
                    visibleFramePresent :=
                        IF mutationKind = "location" THEN FALSE ELSE visibleFramePresent ||
                    publicationState := "published" ||
                    invalidationActive := TRUE ||
                    deferredSaveNeeded := TRUE ||
                    pendingOutcome := "success" ||
                    mutationPhase := "waitingRuntimeDeactivation" ||
                    sawCommittedRetryFailure := TRUE;
                };
            } else {
                requestResult := "none" ||
                pendingOutcome := "failure" ||
                mutationPhase :=
                    IF mutationKind = "source" /\ credentialMutationAttempted
                    THEN "restoringCredential"
                    ELSE "finishing" ||
                sawCommittedRetryFailure := TRUE;
            };
        } else if (mutationPhase = "waitingRuntimeDeactivation") {
            mutationPhase :=
                IF mutationKind = "location"
                THEN "waitingProjectionWorkerReset"
                ELSE "waitingCoordinatorConfigure";
        } else if (mutationPhase = "waitingProjectionWorkerReset") {
            mutationPhase := "waitingCoordinatorConfigure";
        } else if (mutationPhase = "waitingCoordinatorConfigure") {
            mutationPhase := "waitingCoordinatorState";
        } else if (mutationPhase = "waitingCoordinatorState") {
            mutationPhase :=
                IF mutationKind = "source"
                THEN "waitingDiscardFade"
                ELSE "completingInvalidation";
        } else if (mutationPhase = "waitingDiscardFade") {
            visibleFramePresent := FALSE ||
            mutationPhase := "waitingDiscardWorkerReset";
        } else if (mutationPhase = "waitingDiscardWorkerReset") {
            mutationPhase := "completingInvalidation";
        } else if (mutationPhase = "completingInvalidation") {
            invalidationActive := FALSE ||
            mutationPhase := "finishing";
        } else if (mutationPhase = "restoringCredential") {
            either {
                credentials := credentials \ {1} ||
                mutationPhase := "finishing";
            } or {
                mutationPhase := "finishing";
            };
        } else if (mutationPhase = "finishing") {
            if (deferredSaveNeeded) {
                reportedOutcome := pendingOutcome ||
                queuedForegroundSnapshot := livePreferences ||
                requestKind := "foreground" ||
                requestPreferences := livePreferences ||
                foregroundEditQueued := FALSE ||
                deferredSaveNeeded := FALSE ||
                sawRetryRecoveryQueued := sawRetryRecoveryQueued \/
                    (pendingOutcome = "success" /\ sawCommittedRetryFailure) ||
                mutationPhase := "done";
            } else {
                reportedOutcome := pendingOutcome ||
                mutationPhase := "done";
            };
        } else {
            await mutationPhase = "done";
            skip;
        };
    }
}

fair process (PreferenceWorker = "PreferenceWorker") {
PreferenceWorkerStep:
    while (TRUE) {
        await workerPhase = "initialBusy" \/
              (workerPhase = "idle" /\ requestKind # "none") \/
              workerPhase = "saving";
        if (workerPhase = "initialBusy") {
            workerPhase := "idle";
        } else if (workerPhase = "idle") {
            workerPhase := "saving" ||
            workerKind := requestKind ||
            workerPreferences := requestPreferences ||
            requestKind := "none";
        } else if (workerKind = "mutation") {
            if (Implementation = "brokenRetry" /\ saveAttempts = 0) {
                durablePreferences := workerPreferences ||
                requestResult := "success" ||
                workerPhase := "idle" ||
                workerKind := "none" ||
                saveAttempts := saveAttempts + 1;
            } else if (Implementation = "brokenRetry") {
                requestResult := "failure" ||
                workerPhase := "idle" ||
                workerKind := "none" ||
                saveAttempts := saveAttempts + 1;
            } else {
                either {
                    durablePreferences := workerPreferences ||
                    requestResult := "success" ||
                    workerPhase := "idle" ||
                    workerKind := "none" ||
                    saveAttempts := saveAttempts + 1;
                } or {
                    requestResult := "failure" ||
                    workerPhase := "idle" ||
                    workerKind := "none" ||
                    saveAttempts := saveAttempts + 1;
                };
            };
        } else {
            either {
                durablePreferences := workerPreferences ||
                workerPhase := "idle" ||
                workerKind := "none" ||
                sawForegroundSaveComplete := TRUE;
            } or {
                workerPhase := "idle" ||
                workerKind := "none" ||
                sawForegroundSaveComplete := TRUE;
            };
        };
    }
}

fair process (ForegroundEditor = "ForegroundEditor") {
ForegroundEditStep:
    while (TRUE) {
        await foregroundEditCount < MaxForegroundEdits /\ mutationPhase \in AwaitPhases;
        with (nextEdit = foregroundEditCount + 1) {
            livePreferences := [
                source |-> livePreferences.source,
                observer |-> livePreferences.observer,
                edit |-> nextEdit
            ] ||
            foregroundEditCount := nextEdit ||
            foregroundEditQueued := TRUE ||
            deferredSaveNeeded := TRUE;
        };
    }
}

fair process (Activation = "Activation") {
ActivationStep:
    while (TRUE) {
        await (activationState = "none" /\
               mutationPhase = "done" /\
               reportedOutcome = "success" /\
               ~invalidationActive) \/
              activationState = "preparing";
        if (activationState = "none") {
            preparedActivationContextGeneration := contextGeneration ||
            preparedActivationObserverGeneration := publishedObserverGeneration ||
            preparedActivationObserver := livePreferences.observer ||
            activationState := "preparing";
        } else if (preparedActivationContextGeneration = contextGeneration /\
                   preparedActivationObserverGeneration = publishedObserverGeneration /\
                   preparedActivationObserver = livePreferences.observer /\
                   ~invalidationActive) {
            activationContextGeneration := preparedActivationContextGeneration ||
            activationObserverGeneration := preparedActivationObserverGeneration ||
            activationObserver := preparedActivationObserver ||
            activationState := "active";
        } else {
            activationState := "none" ||
            sawStaleActivationRejected := TRUE;
        };
    }
}

fair process (Renderer = "Renderer") {
RendererStep:
    while (TRUE) {
        await (renderState = "idle" /\ activationState = "active" /\
               ~invalidationActive) \/ renderState = "rendering";
        if (renderState = "idle") {
            renderContextGeneration := activationContextGeneration ||
            renderObserverGeneration := activationObserverGeneration ||
            renderObserver := activationObserver ||
            renderState := "rendering";
        } else if (renderContextGeneration = contextGeneration /\
                   renderContextGeneration = activationContextGeneration /\
                   renderObserverGeneration = publishedObserverGeneration /\
                   renderObserverGeneration = activationObserverGeneration /\
                   renderObserver = livePreferences.observer /\
                   renderObserver = activationObserver /\
                   activationState = "active" /\
                   ~invalidationActive) {
            visibleFramePresent := TRUE ||
            visibleFrameObserverGeneration := renderObserverGeneration ||
            visibleFrameObserver := renderObserver ||
            renderState := "idle";
        } else {
            renderState := "idle" ||
            sawStaleRenderRejected := TRUE;
        };
    }
}

process (Done = "Done") {
DoneStep:
    while (TRUE) {
        await Quiescent;
        skip;
    }
}
} *)

TypeOK ==
    /\ mutationKind \in {"none", "source", "location"}
    /\ mutationPhase \in Phases
    /\ livePreferences \in PreferenceValues
    /\ durablePreferences \in PreferenceValues
    /\ credentials \in SUBSET CredentialIDs
    /\ credentialMutationAttempted \in BOOLEAN
    /\ candidateBase \in PreferenceValues
    /\ candidatePreferences \in PreferenceValues
    /\ committedCandidate \in PreferenceValues
    /\ commitKnown \in BOOLEAN
    /\ pendingOutcome \in Outcomes
    /\ reportedOutcome \in Outcomes
    /\ foregroundEditCount \in EditRevisions
    /\ foregroundEditQueued \in BOOLEAN
    /\ deferredSaveNeeded \in BOOLEAN
    /\ queuedForegroundSnapshot \in PreferenceValues
    /\ requestKind \in RequestKinds
    /\ requestPreferences \in PreferenceValues
    /\ requestResult \in Outcomes
    /\ workerPhase \in WorkerPhases
    /\ workerKind \in RequestKinds
    /\ workerPreferences \in PreferenceValues
    /\ saveAttempts \in 0..(MaxForegroundEdits + 1)
    /\ publicationState \in PublicationStates
    /\ invalidationActive \in BOOLEAN
    /\ contextGeneration \in 0..1
    /\ observerGeneration \in 0..1
    /\ publishedObserverGeneration \in 0..1
    /\ activationState \in ActivationStates
    /\ activationContextGeneration \in -1..1
    /\ activationObserverGeneration \in -1..1
    /\ activationObserver \in Observers
    /\ preparedActivationContextGeneration \in 0..1
    /\ preparedActivationObserverGeneration \in 0..1
    /\ preparedActivationObserver \in Observers
    /\ renderState \in RenderStates
    /\ renderContextGeneration \in 0..1
    /\ renderObserverGeneration \in 0..1
    /\ renderObserver \in Observers
    /\ visibleFramePresent \in BOOLEAN
    /\ visibleFrameObserverGeneration \in 0..1
    /\ visibleFrameObserver \in Observers
    /\ sawDrift \in BOOLEAN
    /\ sawCommittedRetryFailure \in BOOLEAN
    /\ sawRetryRecoveryQueued \in BOOLEAN
    /\ sawObserverEarlyPublication \in BOOLEAN
    /\ sawStaleRenderRejected \in BOOLEAN
    /\ sawStaleActivationRejected \in BOOLEAN
    /\ sawForegroundSaveComplete \in BOOLEAN

ReportedFailureKeepsDurableSetup ==
    reportedOutcome = "failure" =>
        /\ durablePreferences.source = livePreferences.source
        /\ durablePreferences.observer = livePreferences.observer

PersistedSourceHasAlignedCredential ==
    durablePreferences.source = 0 \/ durablePreferences.source \in credentials

VisibleFrameMatchesPublishedObserver ==
    visibleFramePresent =>
        /\ visibleFrameObserverGeneration = publishedObserverGeneration
        /\ visibleFrameObserver = livePreferences.observer

ActiveProjectionMatchesPublishedObserver ==
    activationState = "active" =>
        /\ activationContextGeneration = contextGeneration
        /\ activationObserverGeneration = publishedObserverGeneration
        /\ activationObserver = livePreferences.observer

PublicationFollowsDurableCommit ==
    publicationState = "notPublished" \/ commitKnown

EventuallyReports ==
    mutationKind # "none" ~> reportedOutcome # "none"

EventuallyQuiescent ==
    mutationKind # "none" ~> Quiescent

RetryRecoveryWasNotQueued == ~sawRetryRecoveryQueued
ObserverEarlyPublicationWasNotReached == ~sawObserverEarlyPublication
StaleRenderWasNotRejected == ~sawStaleRenderRejected

====
