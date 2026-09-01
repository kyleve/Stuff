---- MODULE ProjectionActivation ----
EXTENDS FiniteSets, Integers, Sequences

CONSTANTS Implementation, SceneCount, OutputCount, Events

AllowedImplementations == {
    "current", "exposesStopped", "identityOnly", "noRuntimeTombstone"
}
AllowedEvents == {
    "scene1On", "scene1Off", "scene2On", "scene2Off",
    "output1On", "output1Off", "output2On", "output2Off",
    "quietOn", "quietOff", "calibrationOn", "calibrationOff"
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

CommandKinds == {"activate", "deactivate"}
LifecycleCommand(kind, lease) == [kind |-> kind, lease |-> lease]
LifecycleCommands == [kind : CommandKinds, lease : LeaseIDs]

PollRequest(kind, lease, revision) ==
    [kind |-> kind, lease |-> lease, revision |-> revision]
PollRequests == [
    kind : CommandKinds,
    lease : LeaseIDs,
    revision : 1..Len(Events)
]
NoPollRequest == [kind |-> "none", lease |-> 0, revision |-> 0]

TeardownEffect(command, victim) == [command |-> command, victim |-> victim]
TeardownEffects == [command : LeaseIDs, victim : LeaseIDs]

ReconcilePhases == {"idle", "captured", "coordinated", "synchronized"}
PollOperationPhases == {"idle", "draining", "starting"}

QueueHasTeardownFor(queue, victims) ==
    \E index \in 1..Len(queue) :
        /\ queue[index].kind = "deactivate"
        /\ \A victim \in victims : queue[index].lease >= victim

PollQueueHasCurrentTeardownFor(queue, victims, currentRevision) ==
    \E index \in 1..Len(queue) :
        /\ queue[index].kind = "deactivate"
        /\ queue[index].revision = currentRevision
        /\ \A victim \in victims : queue[index].lease >= victim

SingleSceneEvents ==
    <<"scene1On", "output1On", "quietOn", "quietOff",
      "calibrationOn", "calibrationOff", "scene1Off">>

TwoSceneEvents ==
    <<"scene1On", "scene2On", "output1On", "output2On",
      "scene1Off", "quietOn", "quietOff", "calibrationOn",
      "calibrationOff", "scene2Off", "output1Off", "output2Off">>

LeaseReplacementRace ==
    <<"scene1On", "output1On", "quietOn", "quietOff">>

(* --algorithm ProjectionActivationAlgorithm {
variables submitted = 0,
          foregroundScenes = {},
          connectedOutputs = {},
          quietRequested = FALSE,
          calibrationRequested = FALSE,
          requestRevision = 0,
          reconcilePhase = "idle",
          capturedRevision = 0,
          capturedPermit = FALSE,
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
          runtimeLease = 0,
          latestRuntimeLease = 0,
          pollRequestRevision = 0,
          pollQueue = <<>>,
          pollOperationPhase = "idle",
          pollOperation = NoPollRequest,
          physicalPollers = {},
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
          sawCalibrationBlock = FALSE;

define {
    RawPermit ==
        /\ foregroundScenes /= {}
        /\ connectedOutputs /= {}
        /\ ~quietRequested
        /\ ~calibrationRequested

    LatestReconciliationPending ==
        \/ reconciledRevision /= requestRevision
        \/ reconcilePhase /= "idle"

    TeardownPending ==
        \/ QueueHasTeardownFor(actionQueue, physicalPollers)
        \/ QueueHasTeardownFor(runtimeQueue, physicalPollers)
        \/ PollQueueHasCurrentTeardownFor(
               pollQueue,
               physicalPollers,
               pollRequestRevision)
        \/ pollOperationPhase = "draining"

    Quiescent ==
        /\ submitted = Len(Events)
        /\ reconcilePhase = "idle"
        /\ reconciledRevision = requestRevision
        /\ actionQueue = <<>>
        /\ runtimeQueue = <<>>
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
                if (~RawPermit /\ physicalPollers /= {}) {
                    sawPendingPermitTeardown := TRUE;
                };
            };
        };
    }
}

fair process (Reconciler = <<"Reconciler", 0>>) {
CaptureLatest:
    while (TRUE) {
        await reconcilePhase = "idle" /\ capturedRevision /= requestRevision;
        capturedRevision := requestRevision ||
        capturedPermit := RawPermit ||
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
        if ((coordinatorRunning \/ Implementation = "exposesStopped") /\
            coordinatorLease /= 0 /\ coordinatorLease >= latestSessionLease) {
            sessionLease := coordinatorLease ||
            latestSessionLease := coordinatorLease ||
            sawDirectLeaseSync := TRUE;
        };
        reconcilePhase := "synchronized";

ApplyIfCurrent:
        await reconcilePhase = "synchronized";
        if (capturedRevision = requestRevision) {
            if (capturedPermit /\ sessionLease /= 0 /\ runtimeLease /= sessionLease) {
                runtimeQueue := Append(
                    runtimeQueue,
                    LifecycleCommand("activate", sessionLease)
                );
            } else if (~capturedPermit /\ sessionLease /= 0) {
                runtimeQueue := Append(
                    runtimeQueue,
                    LifecycleCommand("deactivate", sessionLease)
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
                if (command.lease >= latestSessionLease) {
                    sessionLease := command.lease ||
                    latestSessionLease := command.lease;
                };
            } else if (sessionLease /= 0) {
                if (command.lease < sessionLease) {
                    sawStaleTeardownCommand := TRUE;
                };
                if (Implementation /= "identityOnly") {
                    if (sessionLease = command.lease) {
                        teardownHistory := teardownHistory \cup {
                            TeardownEffect(command.lease, sessionLease)
                        } ||
                        sessionLease := 0 ||
                        runtimeQueue := Append(runtimeQueue, command);
                    };
                } else {
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
            if (command.kind = "activate") {
                if (Implementation = "noRuntimeTombstone" /\
                    command.lease >= latestRuntimeLease) {
                    with (revision = pollRequestRevision + 1) {
                        runtimeLease := command.lease ||
                        latestRuntimeLease := command.lease ||
                        pollRequestRevision := revision ||
                        pollQueue := Append(
                            pollQueue,
                            PollRequest("activate", command.lease, revision)
                        );
                    };
                } else if (Implementation /= "noRuntimeTombstone" /\
                           command.lease > latestRuntimeLease) {
                    with (revision = pollRequestRevision + 1) {
                        runtimeLease := command.lease ||
                        latestRuntimeLease := command.lease ||
                        pollRequestRevision := revision ||
                        pollQueue := Append(
                            pollQueue,
                            PollRequest("activate", command.lease, revision)
                        );
                    };
                };
            } else if (Implementation = "noRuntimeTombstone") {
                if (runtimeLease = command.lease) {
                    with (revision = pollRequestRevision + 1) {
                        runtimeLease := 0 ||
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
            sawPhysicalPoller := TRUE ||
            sawPendingPermitTeardown := sawPendingPermitTeardown \/ ~RawPermit;
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
    /\ requestRevision \in 0..Len(Events)
    /\ reconcilePhase \in ReconcilePhases
    /\ capturedRevision \in 0..Len(Events)
    /\ capturedPermit \in BOOLEAN
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
    /\ runtimeLease \in OptionalLeaseIDs
    /\ latestRuntimeLease \in OptionalLeaseIDs
    /\ pollRequestRevision \in 0..Len(Events)
    /\ pollQueue \in Seq(PollRequests)
    /\ pollOperationPhase \in PollOperationPhases
    /\ pollOperation \in PollRequests \cup {NoPollRequest}
    /\ physicalPollers \subseteq LeaseIDs
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

OwnershipUsesIssuedLeases ==
    /\ (coordinatorLease = 0 \/ coordinatorLease \in issuedLeases)
    /\ (sessionLease = 0 \/ sessionLease \in issuedLeases)
    /\ (runtimeLease = 0 \/ runtimeLease \in issuedLeases)
    /\ physicalPollers \subseteq issuedLeases

NoStaleTeardownOfNewerLease ==
    \A effect \in teardownHistory : effect.command = effect.victim

AtMostOnePhysicalPoller == Cardinality(physicalPollers) <= 1

PermitSafety ==
    physicalPollers /= {} /\ ~RawPermit =>
        LatestReconciliationPending \/ TeardownPending

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

====
