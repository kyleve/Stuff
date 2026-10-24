---- MODULE ProjectionActivation ----
EXTENDS FiniteSets, Integers, Sequences

CONSTANTS Implementation, SceneCount, OutputCount, Events

AllowedImplementations == {
    "current", "exposesStopped", "identityOnly", "noRuntimeTombstone",
    "retainsContextLease", "retiresOnSuspend", "noDemandTombstone"
}
AllowedEvents == {
    "scene1On", "scene1Off", "scene2On", "scene2Off",
    "output1On", "output1Off", "output2On", "output2Off",
    "quietOn", "quietOff", "calibrationOn", "calibrationOff",
    "contextChange", "pollingBlockOn", "pollingBlockOff"
}

EventIsValid(event) ==
    /\ event \in AllowedEvents
    /\ (event \in {"scene2On", "scene2Off"} => SceneCount = 2)
    /\ (event \in {"output2On", "output2Off"} => OutputCount = 2)

ASSUME /\ Implementation \in AllowedImplementations
       /\ SceneCount \in 1..2
       /\ OutputCount \in 1..2
       /\ Events \in Seq(AllowedEvents)
       /\ Len(Events) > 0
       /\ \A index \in 1..Len(Events) : EventIsValid(Events[index])

SceneIDs == 1..SceneCount
OutputIDs == 1..OutputCount
LeaseIDs == 1..Len(Events)
OptionalLeaseIDs == 0..Len(Events)
WorkRevisionLimit == 4 * Len(Events)
WorkRevisions == 1..WorkRevisionLimit
OptionalWorkRevisions == 0..WorkRevisionLimit

CommandKinds == {"activate", "deactivate"}
LifecycleCommand(kind, lease) == [kind |-> kind, lease |-> lease]
LifecycleCommands == [kind : CommandKinds, lease : LeaseIDs]

PollRequest(kind, lease, revision) ==
    [kind |-> kind, lease |-> lease, revision |-> revision]
PollRequests == [
    kind : CommandKinds,
    lease : LeaseIDs,
    revision : WorkRevisions
]
NoPollRequest == [kind |-> "none", lease |-> 0, revision |-> 0]

DemandKinds == {"activate", "suspend"}
DemandCommand(kind, lease, generation) ==
    [kind |-> kind, lease |-> lease, generation |-> generation]
DemandCommands == [
    kind : DemandKinds,
    lease : LeaseIDs,
    generation : 1..Len(Events)
]

TeardownEffect(command, victim) == [command |-> command, victim |-> victim]
TeardownEffects == [command : LeaseIDs, victim : LeaseIDs]

ReconcilePhases == {"idle", "captured", "coordinated", "synchronized"}
PollOperationPhases == {"idle", "draining", "starting"}
InvalidationPhases == {
    "idle", "prepared", "renewed", "runtimeRetired", "successorSynchronized"
}
PollingDemandStates == {"none", "polling", "stopped"}

RemoveAt(sequence, index) ==
    SubSeq(sequence, 1, index - 1) \o
        SubSeq(sequence, index + 1, Len(sequence))

QueueHasTeardownFor(queue, victims) ==
    \E index \in 1..Len(queue) :
        /\ queue[index].kind = "deactivate"
        /\ \A victim \in victims : queue[index].lease >= victim

PollQueueHasCurrentTeardownFor(queue, victims, currentRevision) ==
    \E index \in 1..Len(queue) :
        /\ queue[index].kind = "deactivate"
        /\ queue[index].revision = currentRevision
        /\ \A victim \in victims : queue[index].lease >= victim

DemandQueueHasCurrentSuspensionFor(queue, victims, currentGeneration) ==
    \E index \in 1..Len(queue) :
        /\ queue[index].kind = "suspend"
        /\ queue[index].generation = currentGeneration
        /\ \A victim \in victims : queue[index].lease >= victim

SingleSceneEvents ==
    <<"scene1On", "output1On", "quietOn", "quietOff",
      "calibrationOn", "calibrationOff", "scene1Off">>

TwoSceneEvents ==
    <<"scene1On", "scene2On", "output1On", "output2On",
      "scene1Off", "quietOn", "quietOff", "calibrationOn",
      "calibrationOff", "scene2Off", "output1Off", "output2Off">>

TwoSceneOverlapEvents ==
    <<"scene1On", "scene2On", "output1On", "scene1Off", "scene2Off">>

LeaseReplacementRace ==
    <<"scene1On", "output1On", "quietOn", "quietOff">>

ContextRenewalEvents ==
    <<"scene1On", "output1On", "contextChange">>

PhysicalSuspensionEvents ==
    <<"scene1On", "output1On", "pollingBlockOn", "pollingBlockOff">>

ContextAndSuspensionEvents ==
    <<"scene1On", "output1On", "contextChange",
      "pollingBlockOn", "pollingBlockOff">>

(* --algorithm ProjectionActivationAlgorithm {
variables submitted = 0,
          foregroundScenes = {},
          connectedOutputs = {},
          quietRequested = FALSE,
          calibrationRequested = FALSE,
          pollingBlocked = FALSE,
          requestRevision = 0,
          reconcilePhase = "idle",
          capturedRevision = 0,
          capturedPermit = FALSE,
          capturedPollingBlocked = FALSE,
          capturedSessionLease = 0,
          reconciledRevision = 0,
          reconciledPermit = FALSE,
          coordinatorRunning = FALSE,
          coordinatorLease = 0,
          nextLease = 0,
          issuedLeases = {},
          actionQueue = <<>>,
          sessionLease = 0,
          latestSessionLease = 0,
          runtimeQueue = <<>>,
          demandQueue = <<>>,
          runtimeLease = 0,
          latestRuntimeLease = 0,
          pollDemandState = "none",
          pollDemandGeneration = 0,
          pollRequestRevision = 0,
          pollQueue = <<>>,
          pollOperationPhase = "idle",
          pollOperation = NoPollRequest,
          physicalPollers = {},
          lastStartedPollRevision = 0,
          lastSuspendedLease = 0,
          lastSuspendedPollRevision = 0,
          contextRevision = 0,
          invalidationPhase = "idle",
          invalidationLease = 0,
          lastContextLease = 0,
          lastContextPollRevision = 0,
          teardownHistory = {},
          sawPermitGap = FALSE,
          sawPendingPermitTeardown = FALSE,
          sawDirectLeaseSync = FALSE,
          sawStaleTeardownCommand = FALSE,
          sawNewerRuntimeTeardown = FALSE,
          sawPhysicalDrain = FALSE,
          sawPhysicalPoller = FALSE,
          sawTwoForegroundScenes = FALSE,
          sawQuietBlock = FALSE,
          sawCalibrationBlock = FALSE,
          sawContextGate = FALSE,
          sawContextRenewal = FALSE,
          sawGatedSuccessorSync = FALSE,
          sawContextPoller = FALSE,
          sawOldActivationWhileGatedAfterSuccessor = FALSE,
          sawOldActivationAfterSuccessor = FALSE,
          sawDelayedRuntimeTeardownAfterSuccessor = FALSE,
          sawPhysicalSuspension = FALSE,
          sawSameLeaseResume = FALSE,
          sawDemandOvertake = FALSE;

define {
    RawPermit ==
        /\ foregroundScenes /= {}
        /\ connectedOutputs /= {}
        /\ ~quietRequested
        /\ ~calibrationRequested

    RawPhysicalPermit ==
        /\ RawPermit
        /\ ~pollingBlocked
        /\ invalidationPhase = "idle"

    RuntimeAcceptsLease(lease) ==
        IF runtimeLease /= 0
            THEN lease >= runtimeLease
            ELSE \/ latestRuntimeLease = 0
                 \/ lease > latestRuntimeLease
                 \/ /\ Implementation = "noRuntimeTombstone"
                    /\ lease = latestRuntimeLease

    PollDemandAcceptsActivation(generation) ==
        \/ pollDemandState = "none"
        \/ /\ pollDemandState = "polling"
           /\ generation >= pollDemandGeneration
        \/ /\ pollDemandState = "stopped"
           /\ generation > pollDemandGeneration

    PollDemandAcceptsSuspension(generation) ==
        \/ pollDemandState = "none"
        \/ generation >= pollDemandGeneration

    LatestReconciliationPending ==
        \/ reconciledRevision /= requestRevision
        \/ reconcilePhase /= "idle"
        \/ invalidationPhase /= "idle"

    TeardownPending ==
        \/ QueueHasTeardownFor(actionQueue, physicalPollers)
        \/ QueueHasTeardownFor(runtimeQueue, physicalPollers)
        \/ DemandQueueHasCurrentSuspensionFor(
               demandQueue,
               physicalPollers,
               requestRevision)
        \/ PollQueueHasCurrentTeardownFor(
               pollQueue,
               physicalPollers,
               pollRequestRevision)
        \/ pollOperationPhase = "draining"
        \/ invalidationPhase \in {
               "renewed", "runtimeRetired", "successorSynchronized"
           }

    Quiescent ==
        /\ submitted = Len(Events)
        /\ reconcilePhase = "idle"
        /\ reconciledRevision = requestRevision
        /\ invalidationPhase = "idle"
        /\ actionQueue = <<>>
        /\ runtimeQueue = <<>>
        /\ demandQueue = <<>>
        /\ pollQueue = <<>>
        /\ pollOperationPhase = "idle"

    QuiescentAgreement ==
        /\ Quiescent
        /\ reconciledPermit = RawPermit
        /\ coordinatorRunning = RawPermit
        /\ IF RawPermit
              THEN /\ coordinatorLease \in LeaseIDs
                   /\ sessionLease = coordinatorLease
                   /\ runtimeLease = coordinatorLease
                   /\ IF pollingBlocked
                         THEN /\ pollDemandState = "stopped"
                              /\ physicalPollers = {}
                         ELSE /\ pollDemandState = "polling"
                              /\ physicalPollers = {coordinatorLease}
              ELSE /\ sessionLease = 0
                   /\ runtimeLease = 0
                   /\ physicalPollers = {}
}

fair process (Environment = <<"Environment", 0>>) {
SubmitEvent:
    while (TRUE) {
        await submitted < Len(Events);
        with (index = submitted + 1) {
            with (event = Events[index]) {
                await event /= "contextChange" \/ invalidationPhase = "idle";
                if (event = "scene1On") {
                    foregroundScenes := foregroundScenes \cup {1};
                } else if (event = "scene1Off") {
                    foregroundScenes := foregroundScenes \ {1};
                } else if (event = "scene2On") {
                    foregroundScenes := foregroundScenes \cup {2};
                } else if (event = "scene2Off") {
                    foregroundScenes := foregroundScenes \ {2};
                } else if (event = "output1On") {
                    connectedOutputs := connectedOutputs \cup {1};
                } else if (event = "output1Off") {
                    connectedOutputs := connectedOutputs \ {1};
                } else if (event = "output2On") {
                    connectedOutputs := connectedOutputs \cup {2};
                } else if (event = "output2Off") {
                    connectedOutputs := connectedOutputs \ {2};
                } else if (event = "quietOn") {
                    quietRequested := TRUE;
                } else if (event = "quietOff") {
                    quietRequested := FALSE;
                } else if (event = "calibrationOn") {
                    calibrationRequested := TRUE;
                } else if (event = "calibrationOff") {
                    calibrationRequested := FALSE;
                } else if (event = "pollingBlockOn") {
                    pollingBlocked := TRUE;
                } else if (event = "pollingBlockOff") {
                    pollingBlocked := FALSE;
                } else if (event = "contextChange") {
                    contextRevision := contextRevision + 1 ||
                    invalidationPhase := "prepared" ||
                    sawContextGate := TRUE;
                    if (sessionLease /= 0) {
                        invalidationLease := sessionLease ||
                        lastContextLease := sessionLease ||
                        lastContextPollRevision := lastStartedPollRevision ||
                        latestSessionLease := sessionLease ||
                        sessionLease := 0;
                    } else {
                        invalidationLease := 0;
                    };
                };
                submitted := index ||
                requestRevision := index;
                if (Cardinality(foregroundScenes) = 2) {
                    sawTwoForegroundScenes := TRUE;
                };
                if (quietRequested /\ foregroundScenes /= {} /\ connectedOutputs /= {}) {
                    sawQuietBlock := TRUE;
                };
                if (calibrationRequested /\ foregroundScenes /= {} /\ connectedOutputs /= {}) {
                    sawCalibrationBlock := TRUE;
                };
                if (RawPermit /= reconciledPermit) {
                    sawPermitGap := TRUE;
                };
                if (~RawPhysicalPermit /\ physicalPollers /= {}) {
                    sawPendingPermitTeardown := TRUE;
                };
            };
        };
    }
}

fair process (Reconciler = <<"Reconciler", 0>>) {
CaptureLatest:
    while (TRUE) {
        await /\ reconcilePhase = "idle"
              /\ capturedRevision /= requestRevision
              /\ invalidationPhase = "idle";
        capturedRevision := requestRevision ||
        capturedPermit := RawPermit ||
        capturedPollingBlocked := pollingBlocked ||
        capturedSessionLease := sessionLease ||
        reconcilePhase := "captured" ||
        sawPermitGap := sawPermitGap \/ (RawPermit /= reconciledPermit);

ReconcileCoordinator:
        await reconcilePhase = "captured";
        reconciledRevision := capturedRevision ||
        reconciledPermit := capturedPermit ||
        reconcilePhase := "coordinated";
        if (capturedPermit /\ ~coordinatorRunning) {
            with (lease = nextLease + 1) {
                coordinatorRunning := TRUE ||
                coordinatorLease := lease ||
                nextLease := lease ||
                issuedLeases := issuedLeases \cup {lease} ||
                actionQueue := Append(
                    actionQueue,
                    LifecycleCommand("activate", lease)
                );
            };
        } else if (~capturedPermit /\ coordinatorRunning) {
            coordinatorRunning := FALSE ||
            actionQueue := Append(
                actionQueue,
                LifecycleCommand("deactivate", coordinatorLease)
            );
        };

SynchronizeCurrentLease:
        await reconcilePhase = "coordinated";
        if (invalidationPhase = "idle") {
            if ((coordinatorRunning \/ Implementation = "exposesStopped") /\
                coordinatorLease /= 0) {
                sawDirectLeaseSync := TRUE;
                if (sessionLease /= 0 /\ coordinatorLease >= latestSessionLease) {
                    sessionLease := coordinatorLease ||
                    latestSessionLease := coordinatorLease;
                } else if (sessionLease = 0 /\
                           (latestSessionLease = 0 \/
                            coordinatorLease > latestSessionLease \/
                            (Implementation = "exposesStopped" /\
                             coordinatorLease = latestSessionLease))) {
                    sessionLease := coordinatorLease ||
                    latestSessionLease := coordinatorLease;
                };
            } else if (~coordinatorRunning /\ sessionLease /= 0) {
                latestSessionLease := sessionLease ||
                sessionLease := 0 ||
                sawDirectLeaseSync := TRUE;
            };
        };
        reconcilePhase := "synchronized";

ApplyIfCurrent:
        await reconcilePhase = "synchronized";
        if (capturedRevision = requestRevision /\ invalidationPhase = "idle") {
            if (capturedPermit /\ sessionLease /= 0) {
                demandQueue := Append(
                    demandQueue,
                    DemandCommand(
                        IF capturedPollingBlocked THEN "suspend" ELSE "activate",
                        sessionLease,
                        capturedRevision
                    )
                );
            } else if (~capturedPermit /\ capturedSessionLease /= 0) {
                runtimeQueue := Append(
                    runtimeQueue,
                    LifecycleCommand("deactivate", capturedSessionLease)
                );
            };
        };
        reconcilePhase := "idle";
    }
}

fair process (ActionDispatcher = <<"ActionDispatcher", 0>>) {
DispatchCoordinatorAction:
    while (TRUE) {
        await Len(actionQueue) > 0;
        with (command = Head(actionQueue)) {
            actionQueue := Tail(actionQueue);
            if (command.kind = "activate") {
                if (invalidationPhase = "successorSynchronized" /\
                    command.lease < latestSessionLease) {
                    sawOldActivationWhileGatedAfterSuccessor := TRUE;
                };
                if (invalidationPhase = "idle") {
                    if (command.lease < latestSessionLease) {
                        sawOldActivationAfterSuccessor := TRUE;
                    };
                    if (sessionLease /= 0 /\ command.lease >= latestSessionLease) {
                        sessionLease := command.lease ||
                        latestSessionLease := command.lease;
                    } else if (sessionLease = 0 /\
                               (latestSessionLease = 0 \/
                                command.lease > latestSessionLease \/
                                (Implementation = "exposesStopped" /\
                                 command.lease = latestSessionLease))) {
                        sessionLease := command.lease ||
                        latestSessionLease := command.lease;
                    };
                };
            } else {
                if (command.lease < latestSessionLease) {
                    sawStaleTeardownCommand := TRUE;
                };
                if (Implementation /= "identityOnly") {
                    if (command.lease >= latestSessionLease /\
                        (sessionLease = 0 \/ sessionLease <= command.lease)) {
                        if (sessionLease /= 0) {
                            teardownHistory := teardownHistory \cup {
                                TeardownEffect(command.lease, sessionLease)
                            };
                        };
                        latestSessionLease := command.lease ||
                        sessionLease := 0 ||
                        runtimeQueue := Append(runtimeQueue, command);
                    };
                } else if (sessionLease /= 0) {
                    with (victim = sessionLease) {
                        teardownHistory := teardownHistory \cup {
                            TeardownEffect(command.lease, victim)
                        } ||
                        sessionLease := 0 ||
                        runtimeQueue := Append(
                            runtimeQueue,
                            LifecycleCommand("deactivate", victim)
                        );
                    };
                } else if (command.lease >= latestSessionLease) {
                    latestSessionLease := command.lease ||
                    runtimeQueue := Append(runtimeQueue, command);
                };
            };
        };
    }
}

fair process (ContextInvalidator = <<"ContextInvalidator", 0>>) {
RenewExactCoordinatorLease:
    while (TRUE) {
        await invalidationPhase = "prepared";
        if (invalidationLease /= 0 /\
            coordinatorRunning /\
            coordinatorLease = invalidationLease /\
            Implementation /= "retainsContextLease") {
            if (reconciledPermit) {
                with (replacement = nextLease + 1) {
                    coordinatorRunning := TRUE ||
                    coordinatorLease := replacement ||
                    nextLease := replacement ||
                    issuedLeases := issuedLeases \cup {replacement} ||
                    actionQueue := Append(
                        Append(
                            actionQueue,
                            LifecycleCommand("deactivate", invalidationLease)
                        ),
                        LifecycleCommand("activate", replacement)
                    ) ||
                    sawContextRenewal := TRUE;
                };
            } else {
                coordinatorRunning := FALSE ||
                actionQueue := Append(
                    actionQueue,
                    LifecycleCommand("deactivate", invalidationLease)
                );
            };
        };
        invalidationPhase := "renewed";

RetireInvalidatedRuntime:
        await invalidationPhase = "renewed";
        if (invalidationLease /= 0 /\
            invalidationLease >= latestRuntimeLease) {
            with (victim = runtimeLease) {
                latestRuntimeLease := invalidationLease;
                if (victim /= 0 /\ victim <= invalidationLease) {
                    with (revision = pollRequestRevision + 1) {
                        runtimeLease := 0 ||
                        pollDemandState :=
                            IF pollDemandState = "polling"
                                THEN "stopped"
                                ELSE pollDemandState ||
                        pollRequestRevision := revision ||
                        pollQueue := Append(
                            pollQueue,
                            PollRequest("deactivate", invalidationLease, revision)
                        );
                    };
                };
            };
        };
        invalidationPhase := "runtimeRetired";

SynchronizeSuccessorWhileGated:
        await /\ invalidationPhase = "runtimeRetired"
              /\ physicalPollers = {}
              /\ pollQueue = <<>>
              /\ pollOperationPhase = "idle";
        if (coordinatorRunning /\ coordinatorLease /= 0) {
            sawDirectLeaseSync := TRUE;
            if (sessionLease /= 0 /\ coordinatorLease >= latestSessionLease) {
                sessionLease := coordinatorLease ||
                latestSessionLease := coordinatorLease ||
                sawGatedSuccessorSync := sawGatedSuccessorSync \/
                    (invalidationLease /= 0 /\
                     coordinatorLease > invalidationLease);
            } else if (sessionLease = 0 /\
                       (latestSessionLease = 0 \/
                        coordinatorLease > latestSessionLease \/
                        (Implementation = "exposesStopped" /\
                         coordinatorLease = latestSessionLease))) {
                sessionLease := coordinatorLease ||
                latestSessionLease := coordinatorLease ||
                sawGatedSuccessorSync := sawGatedSuccessorSync \/
                    (invalidationLease /= 0 /\
                     coordinatorLease > invalidationLease);
            };
        } else if (~coordinatorRunning /\ sessionLease /= 0) {
            latestSessionLease := sessionLease ||
            sessionLease := 0 ||
            sawDirectLeaseSync := TRUE;
        };
        invalidationPhase := "successorSynchronized";

CompleteInvalidation:
        await invalidationPhase = "successorSynchronized";
        invalidationLease := 0 ||
        invalidationPhase := "idle";
    }
}

fair process (DemandDispatcher = <<"DemandDispatcher", 0>>) {
DispatchPhysicalDemand:
    while (TRUE) {
        await Len(demandQueue) > 0;
        with (index \in 1..Len(demandQueue)) {
            with (command = demandQueue[index]) {
                demandQueue := RemoveAt(demandQueue, index);
                if (command.kind = "activate") {
                    if (pollDemandState = "stopped" /\
                        command.generation < pollDemandGeneration) {
                        sawDemandOvertake := TRUE;
                    };
                    if (RuntimeAcceptsLease(command.lease) /\
                        PollDemandAcceptsActivation(command.generation)) {
                        with (revision = pollRequestRevision + 1) {
                            runtimeLease := command.lease ||
                            latestRuntimeLease :=
                                IF command.lease > latestRuntimeLease
                                    THEN command.lease
                                    ELSE latestRuntimeLease ||
                            pollDemandState := "polling" ||
                            pollDemandGeneration := command.generation ||
                            pollRequestRevision := revision ||
                            pollQueue := Append(
                                pollQueue,
                                PollRequest("activate", command.lease, revision)
                            );
                        };
                    };
                } else if (Implementation = "noDemandTombstone" /\
                           pollDemandState = "none") {
                    skip;
                } else if (RuntimeAcceptsLease(command.lease) /\
                           PollDemandAcceptsSuspension(command.generation)) {
                    if (physicalPollers /= {}) {
                        lastSuspendedLease := command.lease ||
                        lastSuspendedPollRevision := lastStartedPollRevision ||
                        sawPhysicalSuspension := TRUE;
                    };
                    with (revision = pollRequestRevision + 1) {
                        runtimeLease :=
                            IF Implementation = "retiresOnSuspend"
                                THEN 0
                                ELSE command.lease ||
                        latestRuntimeLease :=
                            IF command.lease > latestRuntimeLease
                                THEN command.lease
                                ELSE latestRuntimeLease ||
                        pollDemandState := "stopped" ||
                        pollDemandGeneration := command.generation ||
                        pollRequestRevision := revision ||
                        pollQueue := Append(
                            pollQueue,
                            PollRequest("deactivate", command.lease, revision)
                        );
                    };
                };
            };
        };
    }
}

fair process (RuntimeDispatcher = <<"RuntimeDispatcher", 0>>) {
DispatchRuntimeCommand:
    while (TRUE) {
        await Len(runtimeQueue) > 0;
        with (command = Head(runtimeQueue)) {
            runtimeQueue := Tail(runtimeQueue);
            if (command.kind = "deactivate") {
                if (runtimeLease > command.lease) {
                    sawDelayedRuntimeTeardownAfterSuccessor := TRUE;
                };
                if (Implementation = "noRuntimeTombstone") {
                    if (runtimeLease = command.lease) {
                        with (revision = pollRequestRevision + 1) {
                            runtimeLease := 0 ||
                            pollDemandState :=
                                IF pollDemandState = "polling"
                                    THEN "stopped"
                                    ELSE pollDemandState ||
                            pollRequestRevision := revision ||
                            pollQueue := Append(
                                pollQueue,
                                PollRequest("deactivate", command.lease, revision)
                            );
                        };
                    };
                } else if (command.lease >= latestRuntimeLease) {
                    with (victim = runtimeLease) {
                        sawNewerRuntimeTeardown := sawNewerRuntimeTeardown \/
                            (command.lease > latestRuntimeLease) ||
                        latestRuntimeLease := command.lease;
                        if (victim /= 0 /\ victim <= command.lease) {
                            with (revision = pollRequestRevision + 1) {
                                runtimeLease := 0 ||
                                pollDemandState :=
                                    IF pollDemandState = "polling"
                                        THEN "stopped"
                                        ELSE pollDemandState ||
                                pollRequestRevision := revision ||
                                pollQueue := Append(
                                    pollQueue,
                                    PollRequest("deactivate", command.lease, revision)
                                );
                            };
                        };
                    };
                };
            };
        };
    }
}

fair process (PollBegin = <<"PollBegin", 0>>) {
BeginPollLifecycle:
    while (TRUE) {
        await pollOperationPhase = "idle" /\ Len(pollQueue) > 0;
        with (request = Head(pollQueue)) {
            pollQueue := Tail(pollQueue);
            if (request.revision = pollRequestRevision) {
                pollOperation := request;
                if (physicalPollers /= {}) {
                    pollOperationPhase := "draining" ||
                    sawPhysicalDrain := TRUE;
                } else if (request.kind = "activate") {
                    pollOperationPhase := "starting";
                };
            };
        };
    }
}

fair process (PollDrain = <<"PollDrain", 0>>) {
DrainPhysicalPoller:
    while (TRUE) {
        await pollOperationPhase = "draining";
        physicalPollers := {};
        if (pollOperation.kind = "activate" /\
            pollOperation.revision = pollRequestRevision) {
            pollOperationPhase := "starting";
        } else {
            pollOperationPhase := "idle";
        };
    }
}

fair process (PollStart = <<"PollStart", 0>>) {
StartPhysicalPoller:
    while (TRUE) {
        await pollOperationPhase = "starting";
        if (pollOperation.revision = pollRequestRevision) {
            physicalPollers := {pollOperation.lease} ||
            lastStartedPollRevision := pollOperation.revision ||
            sawPhysicalPoller := TRUE ||
            sawPendingPermitTeardown :=
                sawPendingPermitTeardown \/ ~RawPhysicalPermit ||
            sawContextPoller := sawContextPoller \/
                (lastContextLease /= 0 /\
                 pollOperation.lease > lastContextLease /\
                 pollOperation.revision > lastContextPollRevision) ||
            sawSameLeaseResume := sawSameLeaseResume \/
                (lastSuspendedLease = pollOperation.lease /\
                 pollOperation.revision > lastSuspendedPollRevision);
        };
        pollOperationPhase := "idle";
    }
}

process (Done = <<"Done", 0>>) {
QuiescentStutter:
    while (TRUE) {
        await Quiescent;
        skip;
    }
}
} *)

TypeOK ==
    /\ submitted \in 0..Len(Events)
    /\ foregroundScenes \subseteq SceneIDs
    /\ connectedOutputs \subseteq OutputIDs
    /\ quietRequested \in BOOLEAN
    /\ calibrationRequested \in BOOLEAN
    /\ pollingBlocked \in BOOLEAN
    /\ requestRevision \in 0..Len(Events)
    /\ reconcilePhase \in ReconcilePhases
    /\ capturedRevision \in 0..Len(Events)
    /\ capturedPermit \in BOOLEAN
    /\ capturedPollingBlocked \in BOOLEAN
    /\ capturedSessionLease \in OptionalLeaseIDs
    /\ reconciledRevision \in 0..Len(Events)
    /\ reconciledPermit \in BOOLEAN
    /\ coordinatorRunning \in BOOLEAN
    /\ coordinatorLease \in OptionalLeaseIDs
    /\ nextLease \in 0..Len(Events)
    /\ issuedLeases \subseteq LeaseIDs
    /\ actionQueue \in Seq(LifecycleCommands)
    /\ sessionLease \in OptionalLeaseIDs
    /\ latestSessionLease \in OptionalLeaseIDs
    /\ runtimeQueue \in Seq(LifecycleCommands)
    /\ demandQueue \in Seq(DemandCommands)
    /\ runtimeLease \in OptionalLeaseIDs
    /\ latestRuntimeLease \in OptionalLeaseIDs
    /\ pollDemandState \in PollingDemandStates
    /\ pollDemandGeneration \in 0..Len(Events)
    /\ pollRequestRevision \in OptionalWorkRevisions
    /\ pollQueue \in Seq(PollRequests)
    /\ pollOperationPhase \in PollOperationPhases
    /\ pollOperation \in PollRequests \cup {NoPollRequest}
    /\ physicalPollers \subseteq LeaseIDs
    /\ lastStartedPollRevision \in OptionalWorkRevisions
    /\ lastSuspendedLease \in OptionalLeaseIDs
    /\ lastSuspendedPollRevision \in OptionalWorkRevisions
    /\ contextRevision \in 0..Len(Events)
    /\ invalidationPhase \in InvalidationPhases
    /\ invalidationLease \in OptionalLeaseIDs
    /\ lastContextLease \in OptionalLeaseIDs
    /\ lastContextPollRevision \in OptionalWorkRevisions
    /\ teardownHistory \subseteq TeardownEffects
    /\ sawPermitGap \in BOOLEAN
    /\ sawPendingPermitTeardown \in BOOLEAN
    /\ sawDirectLeaseSync \in BOOLEAN
    /\ sawStaleTeardownCommand \in BOOLEAN
    /\ sawNewerRuntimeTeardown \in BOOLEAN
    /\ sawPhysicalDrain \in BOOLEAN
    /\ sawPhysicalPoller \in BOOLEAN
    /\ sawTwoForegroundScenes \in BOOLEAN
    /\ sawQuietBlock \in BOOLEAN
    /\ sawCalibrationBlock \in BOOLEAN
    /\ sawContextGate \in BOOLEAN
    /\ sawContextRenewal \in BOOLEAN
    /\ sawGatedSuccessorSync \in BOOLEAN
    /\ sawContextPoller \in BOOLEAN
    /\ sawOldActivationWhileGatedAfterSuccessor \in BOOLEAN
    /\ sawOldActivationAfterSuccessor \in BOOLEAN
    /\ sawDelayedRuntimeTeardownAfterSuccessor \in BOOLEAN
    /\ sawPhysicalSuspension \in BOOLEAN
    /\ sawSameLeaseResume \in BOOLEAN
    /\ sawDemandOvertake \in BOOLEAN

OwnershipUsesIssuedLeases ==
    /\ (coordinatorLease = 0 \/ coordinatorLease \in issuedLeases)
    /\ (sessionLease = 0 \/ sessionLease \in issuedLeases)
    /\ (runtimeLease = 0 \/ runtimeLease \in issuedLeases)
    /\ physicalPollers \subseteq issuedLeases

NoStaleTeardownOfNewerLease ==
    \A effect \in teardownHistory : effect.command >= effect.victim

AtMostOnePhysicalPoller == Cardinality(physicalPollers) <= 1

SessionLeaseMatchesHighWater ==
    sessionLease = 0 \/ sessionLease = latestSessionLease

RuntimeLeaseMatchesHighWater ==
    runtimeLease = 0 \/ runtimeLease = latestRuntimeLease

PermitSafety ==
    physicalPollers /= {} /\ ~RawPhysicalPermit =>
        LatestReconciliationPending \/ TeardownPending

FreshContextAtQuiescence ==
    Quiescent /\ RawPermit /\ lastContextLease /= 0 =>
        /\ coordinatorLease > lastContextLease
        /\ sessionLease = coordinatorLease
        /\ runtimeLease = coordinatorLease
        /\ IF pollingBlocked
              THEN physicalPollers = {}
              ELSE /\ physicalPollers = {coordinatorLease}
                   /\ lastStartedPollRevision > lastContextPollRevision

FreshPhysicalResumeAtQuiescence ==
    Quiescent /\ RawPermit /\ ~pollingBlocked /\
    lastSuspendedLease = coordinatorLease =>
        lastStartedPollRevision > lastSuspendedPollRevision

CorrectAtQuiescence == Quiescent => QuiescentAgreement

EventuallyConverges == submitted = Len(Events) ~> QuiescentAgreement

PermitGapNotReached == ~sawPermitGap
PendingPermitTeardownNotReached == ~sawPendingPermitTeardown
DirectLeaseSyncNotReached == ~sawDirectLeaseSync
StaleTeardownCommandNotReached == ~sawStaleTeardownCommand
NewerRuntimeTeardownNotReached == ~sawNewerRuntimeTeardown
PhysicalDrainNotReached == ~sawPhysicalDrain
PhysicalPollerNotReached == ~sawPhysicalPoller
TwoForegroundScenesNotReached == ~sawTwoForegroundScenes
QuietBlockNotReached == ~sawQuietBlock
CalibrationBlockNotReached == ~sawCalibrationBlock
ContextGateNotReached == ~sawContextGate
ContextRenewalNotReached == ~sawContextRenewal
GatedSuccessorSyncNotReached == ~sawGatedSuccessorSync
ContextPollerNotReached == ~sawContextPoller
OldActivationWhileGatedAfterSuccessorNotReached ==
    ~sawOldActivationWhileGatedAfterSuccessor
OldActivationAfterSuccessorNotReached == ~sawOldActivationAfterSuccessor
DelayedRuntimeTeardownAfterSuccessorNotReached ==
    ~sawDelayedRuntimeTeardownAfterSuccessor
PhysicalSuspensionNotReached == ~sawPhysicalSuspension
SameLeaseResumeNotReached == ~sawSameLeaseResume
DemandOvertakeNotReached == ~sawDemandOvertake

====
