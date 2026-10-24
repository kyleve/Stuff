---- MODULE PreferenceTransactions ----
EXTENDS Integers, Sequences, FiniteSets

CONSTANTS Implementation, MutationKinds, MaxForegroundEdits

ASSUME /\ Implementation \in {
            "current", "brokenRetry", "brokenObserver", "brokenInvalidation"
           }
       /\ MutationKinds \subseteq {"source", "location"}
       /\ MutationKinds # {}
       /\ MaxForegroundEdits \in 0..2
       /\ (Implementation = "brokenRetry" => MutationKinds = {"source"})
       /\ (Implementation = "brokenObserver" => MutationKinds = {"location"})
       /\ (Implementation = "brokenInvalidation" => MutationKinds = {"source"})

Sources == {0, 1}
Observers == {0, 1}
EditRevisions == 0..MaxForegroundEdits
CredentialIDs == {1}
NoLease == 0
CapturedLeaseEpoch == 1
SuccessorLeaseEpoch == 2
LeaseEpochs == NoLease..SuccessorLeaseEpoch
RenewalResults == {"none", "replaced", "retired", "superseded"}
CallbackKinds == {"activate", "deactivate"}
CallbackPhases == {"idle", "waitingWorker", "waitingRuntime"}

LifecycleCommand(kind, lease) == [kind |-> kind, lease |-> lease]
LifecycleCommands == [kind: CallbackKinds, lease: LeaseEpochs \ {NoLease}]

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
    "waitingLeaseRenewal",
    "waitingRuntimeDeactivation",
    "waitingProjectionWorkerReset",
    "waitingDiscardFade",
    "waitingDiscardWorkerReset",
    "waitingCoordinatorConfigure",
    "waitingCoordinatorState",
    "waitingCoordinatorLease",
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
    "waitingLeaseRenewal",
    "waitingRuntimeDeactivation",
    "waitingProjectionWorkerReset",
    "waitingDiscardFade",
    "waitingDiscardWorkerReset",
    "waitingCoordinatorConfigure",
    "waitingCoordinatorState",
    "waitingCoordinatorLease",
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
          invalidationCompleted = FALSE,
          cleanupComplete = FALSE,
          coordinatorConfigured = FALSE,
          coordinatorStateRead = FALSE,
          leaseSynchronized = FALSE,
          contextGeneration = 0,
          observerGeneration = 0,
          publishedObserverGeneration = 0,
          capturedLease = NoLease,
          renewalResult = "none",
          coordinatorLease = CapturedLeaseEpoch,
          sessionLease = CapturedLeaseEpoch,
          latestSessionLease = CapturedLeaseEpoch,
          runtimeLease = CapturedLeaseEpoch,
          latestRuntimeLease = CapturedLeaseEpoch,
          directRetirementLease = NoLease,
          actionQueue = <<>>,
          callbackPhase = "idle",
          callbackLease = NoLease,
          activationState = "active",
          activationLease = CapturedLeaseEpoch,
          activationContextGeneration = 0,
          activationObserverGeneration = 0,
          activationObserver = 0,
          preparedActivationLease = CapturedLeaseEpoch,
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
          sawForegroundSaveComplete = FALSE,
          sawCapturedLeaseRetirement = FALSE,
          sawOldActivationAfterSuccessorSync = FALSE,
          sawOldDeactivationAfterSuccessorSync = FALSE,
          sawDelayedRuntimeTeardownAfterSuccessor = FALSE,
          sawSuccessorRuntimeActivation = FALSE;

define {
    NextContextGeneration == contextGeneration + 1

    NextObserverGeneration ==
        observerGeneration + IF mutationKind = "location" THEN 1 ELSE 0

    UsesCommittedRecovery ==
        Implementation \in {"current", "brokenInvalidation"}

    RuntimeAccepts(lease) ==
        IF runtimeLease = NoLease
        THEN lease > latestRuntimeLease
        ELSE lease >= runtimeLease

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
                    if (commitKnown /\ UsesCommittedRecovery) {
                        livePreferences := committedCandidate ||
                        contextGeneration := NextContextGeneration ||
                        observerGeneration := NextObserverGeneration ||
                        publishedObserverGeneration := NextObserverGeneration ||
                        capturedLease := sessionLease ||
                        sessionLease := NoLease ||
                        latestSessionLease := sessionLease ||
                        activationState := "none" ||
                        activationLease := NoLease ||
                        activationContextGeneration := -1 ||
                        activationObserverGeneration := -1 ||
                        activationObserver := 0 ||
                        preparedActivationLease := NoLease ||
                        visibleFramePresent :=
                            IF mutationKind = "location" THEN FALSE ELSE visibleFramePresent ||
                        publicationState := "published" ||
                        invalidationActive := TRUE ||
                        invalidationCompleted := FALSE ||
                        cleanupComplete := FALSE ||
                        coordinatorConfigured := FALSE ||
                        coordinatorStateRead := FALSE ||
                        leaseSynchronized := FALSE ||
                        renewalResult := "none" ||
                        actionQueue := Append(
                            actionQueue,
                            LifecycleCommand("activate", sessionLease)
                        ) ||
                        deferredSaveNeeded := TRUE ||
                        pendingOutcome := "success" ||
                        mutationPhase := "waitingLeaseRenewal";
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
                    capturedLease := sessionLease ||
                    sessionLease := NoLease ||
                    latestSessionLease := sessionLease ||
                    activationState := "none" ||
                    activationLease := NoLease ||
                    activationContextGeneration := -1 ||
                    activationObserverGeneration := -1 ||
                    activationObserver := 0 ||
                    preparedActivationLease := NoLease ||
                    visibleFramePresent :=
                        IF mutationKind = "location" THEN FALSE ELSE visibleFramePresent ||
                    publicationState := "published" ||
                    invalidationActive := TRUE ||
                    invalidationCompleted := FALSE ||
                    cleanupComplete := FALSE ||
                    coordinatorConfigured := FALSE ||
                    coordinatorStateRead := FALSE ||
                    leaseSynchronized := FALSE ||
                    renewalResult := "none" ||
                    actionQueue := Append(
                        actionQueue,
                        LifecycleCommand("activate", sessionLease)
                    ) ||
                    foregroundEditQueued := FALSE ||
                    deferredSaveNeeded := FALSE ||
                    pendingOutcome := "success" ||
                    mutationPhase := "waitingLeaseRenewal";
                };
            } else if (~commitKnown) {
                requestResult := "none" ||
                pendingOutcome := "failure" ||
                mutationPhase :=
                    IF mutationKind = "source" /\ credentialMutationAttempted
                    THEN "restoringCredential"
                    ELSE "finishing";
            } else if (UsesCommittedRecovery) {
                either {
                    requestResult := "none" ||
                    livePreferences := MutatedPreferences(livePreferences, mutationKind) ||
                    contextGeneration := NextContextGeneration ||
                    observerGeneration := NextObserverGeneration ||
                    publishedObserverGeneration := NextObserverGeneration ||
                    capturedLease := sessionLease ||
                    sessionLease := NoLease ||
                    latestSessionLease := sessionLease ||
                    activationState := "none" ||
                    activationLease := NoLease ||
                    activationContextGeneration := -1 ||
                    activationObserverGeneration := -1 ||
                    activationObserver := 0 ||
                    preparedActivationLease := NoLease ||
                    visibleFramePresent :=
                        IF mutationKind = "location" THEN FALSE ELSE visibleFramePresent ||
                    publicationState := "published" ||
                    invalidationActive := TRUE ||
                    invalidationCompleted := FALSE ||
                    cleanupComplete := FALSE ||
                    coordinatorConfigured := FALSE ||
                    coordinatorStateRead := FALSE ||
                    leaseSynchronized := FALSE ||
                    renewalResult := "none" ||
                    actionQueue := Append(
                        actionQueue,
                        LifecycleCommand("activate", sessionLease)
                    ) ||
                    deferredSaveNeeded := TRUE ||
                    pendingOutcome := "success" ||
                    mutationPhase := "waitingLeaseRenewal" ||
                    sawCommittedRetryFailure := TRUE;
                } or {
                    requestResult := "none" ||
                    livePreferences := committedCandidate ||
                    contextGeneration := NextContextGeneration ||
                    observerGeneration := NextObserverGeneration ||
                    publishedObserverGeneration := NextObserverGeneration ||
                    capturedLease := sessionLease ||
                    sessionLease := NoLease ||
                    latestSessionLease := sessionLease ||
                    activationState := "none" ||
                    activationLease := NoLease ||
                    activationContextGeneration := -1 ||
                    activationObserverGeneration := -1 ||
                    activationObserver := 0 ||
                    preparedActivationLease := NoLease ||
                    visibleFramePresent :=
                        IF mutationKind = "location" THEN FALSE ELSE visibleFramePresent ||
                    publicationState := "published" ||
                    invalidationActive := TRUE ||
                    invalidationCompleted := FALSE ||
                    cleanupComplete := FALSE ||
                    coordinatorConfigured := FALSE ||
                    coordinatorStateRead := FALSE ||
                    leaseSynchronized := FALSE ||
                    renewalResult := "none" ||
                    actionQueue := Append(
                        actionQueue,
                        LifecycleCommand("activate", sessionLease)
                    ) ||
                    deferredSaveNeeded := TRUE ||
                    pendingOutcome := "success" ||
                    mutationPhase := "waitingLeaseRenewal" ||
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
        } else if (mutationPhase = "waitingLeaseRenewal") {
            either {
                renewalResult := "replaced" ||
                coordinatorLease := SuccessorLeaseEpoch ||
                actionQueue := Append(
                    Append(
                        actionQueue,
                        LifecycleCommand("deactivate", capturedLease)
                    ),
                    LifecycleCommand("activate", SuccessorLeaseEpoch)
                );
            } or {
                renewalResult := "retired" ||
                coordinatorLease := NoLease ||
                actionQueue := Append(
                    actionQueue,
                    LifecycleCommand("deactivate", capturedLease)
                );
            } or {
                renewalResult := "superseded" ||
                coordinatorLease := SuccessorLeaseEpoch ||
                actionQueue := Append(
                    actionQueue,
                    LifecycleCommand("activate", SuccessorLeaseEpoch)
                );
            };
            mutationPhase := "waitingRuntimeDeactivation";
        } else if (mutationPhase = "waitingRuntimeDeactivation") {
            if (capturedLease >= latestRuntimeLease) {
                latestRuntimeLease := capturedLease ||
                runtimeLease :=
                    IF runtimeLease /= NoLease /\ runtimeLease <= capturedLease
                    THEN NoLease
                    ELSE runtimeLease;
            };
            directRetirementLease := capturedLease ||
            sawCapturedLeaseRetirement := TRUE ||
            mutationPhase :=
                IF mutationKind = "location"
                THEN "waitingProjectionWorkerReset"
                ELSE "waitingDiscardFade";
        } else if (mutationPhase = "waitingProjectionWorkerReset") {
            cleanupComplete := TRUE ||
            mutationPhase := "waitingCoordinatorConfigure";
        } else if (mutationPhase = "waitingDiscardFade") {
            visibleFramePresent := FALSE ||
            mutationPhase := "waitingDiscardWorkerReset";
        } else if (mutationPhase = "waitingDiscardWorkerReset") {
            cleanupComplete := TRUE ||
            mutationPhase := "waitingCoordinatorConfigure";
        } else if (mutationPhase = "waitingCoordinatorConfigure") {
            coordinatorConfigured := TRUE ||
            mutationPhase := "waitingCoordinatorState";
        } else if (mutationPhase = "waitingCoordinatorState") {
            coordinatorStateRead := TRUE ||
            mutationPhase :=
                IF Implementation = "brokenInvalidation"
                THEN "completingInvalidation"
                ELSE "waitingCoordinatorLease";
        } else if (mutationPhase = "waitingCoordinatorLease") {
            sessionLease := coordinatorLease ||
            latestSessionLease :=
                IF coordinatorLease > latestSessionLease
                THEN coordinatorLease
                ELSE latestSessionLease ||
            leaseSynchronized := TRUE ||
            mutationPhase := "completingInvalidation";
        } else if (mutationPhase = "completingInvalidation") {
            invalidationActive := FALSE ||
            invalidationCompleted := TRUE ||
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

fair process (ActionDispatcher = "ActionDispatcher") {
DispatchCoordinatorAction:
    while (TRUE) {
        await callbackPhase = "idle" /\ Len(actionQueue) > 0;
        with (command = Head(actionQueue)) {
            actionQueue := Tail(actionQueue);
            if (command.kind = "activate") {
                if (command.lease = capturedLease /\
                    leaseSynchronized /\
                    coordinatorLease = SuccessorLeaseEpoch) {
                    sawOldActivationAfterSuccessorSync := TRUE;
                };
                if (~invalidationActive) {
                    if (sessionLease /= NoLease /\
                        command.lease >= latestSessionLease) {
                        sessionLease := command.lease ||
                        latestSessionLease := command.lease;
                    } else if (sessionLease = NoLease /\
                               (latestSessionLease = NoLease \/
                                command.lease > latestSessionLease)) {
                        sessionLease := command.lease ||
                        latestSessionLease := command.lease;
                    };
                };
            } else {
                if (command.lease = capturedLease /\
                    leaseSynchronized /\
                    coordinatorLease = SuccessorLeaseEpoch) {
                    sawOldDeactivationAfterSuccessorSync := TRUE;
                };
                if (command.lease >= latestSessionLease /\
                    (sessionLease = NoLease \/ sessionLease <= command.lease)) {
                    sessionLease := NoLease ||
                    latestSessionLease := command.lease ||
                    callbackLease := command.lease ||
                    callbackPhase := "waitingWorker";
                };
            };
        };
    }
}

fair process (CallbackCompletion = "CallbackCompletion") {
CompleteCoordinatorWorkerReset:
    while (TRUE) {
        await callbackPhase = "waitingWorker";
        callbackPhase := "waitingRuntime";

CompleteCoordinatorRuntimeDeactivation:
        await callbackPhase = "waitingRuntime";
        if (runtimeLease > callbackLease) {
            sawDelayedRuntimeTeardownAfterSuccessor := TRUE;
        };
        if (callbackLease >= latestRuntimeLease) {
            latestRuntimeLease := callbackLease ||
            runtimeLease :=
                IF runtimeLease /= NoLease /\ runtimeLease <= callbackLease
                THEN NoLease
                ELSE runtimeLease;
        };
        callbackLease := NoLease ||
        callbackPhase := "idle";
    }
}

fair process (Activation = "Activation") {
ActivationStep:
    while (TRUE) {
        await (activationState = "none" /\
               mutationPhase = "done" /\
               reportedOutcome = "success" /\
               sessionLease /= NoLease /\
               ~invalidationActive) \/
              activationState = "preparing";
        if (activationState = "none") {
            preparedActivationLease := sessionLease ||
            preparedActivationContextGeneration := contextGeneration ||
            preparedActivationObserverGeneration := publishedObserverGeneration ||
            preparedActivationObserver := livePreferences.observer ||
            activationState := "preparing";
        } else if (preparedActivationLease = sessionLease /\
                   preparedActivationLease = coordinatorLease /\
                   RuntimeAccepts(preparedActivationLease) /\
                   preparedActivationContextGeneration = contextGeneration /\
                   preparedActivationObserverGeneration = publishedObserverGeneration /\
                   preparedActivationObserver = livePreferences.observer /\
                   ~invalidationActive) {
            runtimeLease := preparedActivationLease ||
            latestRuntimeLease :=
                IF preparedActivationLease > latestRuntimeLease
                THEN preparedActivationLease
                ELSE latestRuntimeLease ||
            activationLease := preparedActivationLease ||
            activationContextGeneration := preparedActivationContextGeneration ||
            activationObserverGeneration := preparedActivationObserverGeneration ||
            activationObserver := preparedActivationObserver ||
            activationState := "active" ||
            sawSuccessorRuntimeActivation :=
                sawSuccessorRuntimeActivation \/
                (preparedActivationLease = SuccessorLeaseEpoch);
        } else {
            activationState := "none" ||
            activationLease := NoLease ||
            preparedActivationLease := NoLease ||
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
    /\ invalidationCompleted \in BOOLEAN
    /\ cleanupComplete \in BOOLEAN
    /\ coordinatorConfigured \in BOOLEAN
    /\ coordinatorStateRead \in BOOLEAN
    /\ leaseSynchronized \in BOOLEAN
    /\ contextGeneration \in 0..1
    /\ observerGeneration \in 0..1
    /\ publishedObserverGeneration \in 0..1
    /\ capturedLease \in LeaseEpochs
    /\ renewalResult \in RenewalResults
    /\ coordinatorLease \in LeaseEpochs
    /\ sessionLease \in LeaseEpochs
    /\ latestSessionLease \in LeaseEpochs
    /\ runtimeLease \in LeaseEpochs
    /\ latestRuntimeLease \in LeaseEpochs
    /\ directRetirementLease \in LeaseEpochs
    /\ actionQueue \in Seq(LifecycleCommands)
    /\ callbackPhase \in CallbackPhases
    /\ callbackLease \in LeaseEpochs
    /\ activationState \in ActivationStates
    /\ activationLease \in LeaseEpochs
    /\ activationContextGeneration \in -1..1
    /\ activationObserverGeneration \in -1..1
    /\ activationObserver \in Observers
    /\ preparedActivationLease \in LeaseEpochs
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
    /\ sawCapturedLeaseRetirement \in BOOLEAN
    /\ sawOldActivationAfterSuccessorSync \in BOOLEAN
    /\ sawOldDeactivationAfterSuccessorSync \in BOOLEAN
    /\ sawDelayedRuntimeTeardownAfterSuccessor \in BOOLEAN
    /\ sawSuccessorRuntimeActivation \in BOOLEAN

LeaseLifecycleShape ==
    /\ (sessionLease = NoLease \/ sessionLease = latestSessionLease)
    /\ (runtimeLease = NoLease \/ runtimeLease = latestRuntimeLease)
    /\ (activationState = "active" => activationLease /= NoLease)
    /\ (activationState /= "active" => activationLease = NoLease)
    /\ (callbackPhase = "idle" => callbackLease = NoLease)
    /\ (callbackPhase /= "idle" => callbackLease /= NoLease)

RenewalResultMatchesAuthority ==
    /\ (renewalResult = "replaced" =>
            /\ capturedLease = CapturedLeaseEpoch
            /\ coordinatorLease = SuccessorLeaseEpoch)
    /\ (renewalResult = "retired" =>
            /\ capturedLease = CapturedLeaseEpoch
            /\ coordinatorLease = NoLease)
    /\ (renewalResult = "superseded" =>
            /\ capturedLease = CapturedLeaseEpoch
            /\ coordinatorLease = SuccessorLeaseEpoch)

CapturedLeaseRetirementIsExact ==
    sawCapturedLeaseRetirement =>
        /\ capturedLease = CapturedLeaseEpoch
        /\ directRetirementLease = capturedLease
        /\ (runtimeLease = NoLease \/ runtimeLease > capturedLease)

InvalidationCompletionFollowsRequiredWork ==
    invalidationCompleted =>
        /\ ~invalidationActive
        /\ renewalResult /= "none"
        /\ sawCapturedLeaseRetirement
        /\ cleanupComplete
        /\ coordinatorConfigured
        /\ coordinatorStateRead
        /\ leaseSynchronized

OldCallbacksPreserveSuccessor ==
    /\ (leaseSynchronized /\ coordinatorLease = SuccessorLeaseEpoch =>
            /\ sessionLease = SuccessorLeaseEpoch
            /\ latestSessionLease = SuccessorLeaseEpoch)
    /\ (sawSuccessorRuntimeActivation =>
            /\ runtimeLease = SuccessorLeaseEpoch
            /\ latestRuntimeLease = SuccessorLeaseEpoch)

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
        /\ activationLease = sessionLease
        /\ activationLease = coordinatorLease
        /\ activationLease = runtimeLease
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
RequiredInvalidationPathNotReached ==
    ~(invalidationCompleted /\ sawCapturedLeaseRetirement /\ leaseSynchronized)
ReplacedRenewalNotReached == renewalResult /= "replaced"
RetiredRenewalNotReached == renewalResult /= "retired"
SupersededRenewalNotReached == renewalResult /= "superseded"
OldCallbacksAfterSuccessorSyncNotReached ==
    ~(sawOldActivationAfterSuccessorSync /\ sawOldDeactivationAfterSuccessorSync)
DelayedRuntimeTeardownAfterSuccessorNotReached ==
    ~sawDelayedRuntimeTeardownAfterSuccessor

====
