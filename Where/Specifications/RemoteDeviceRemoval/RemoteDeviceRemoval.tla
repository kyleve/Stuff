---- MODULE RemoteDeviceRemoval ----
EXTENDS FiniteSets, Integers

CONSTANTS Implementation, MaxTime, Cutoffs

Times == 0..MaxTime
AdvisoryKinds == {"profile", "checkIn", "metadata"}
TargetPhases == {"idle", "reading", "revoking", "clearing", "retired"}
Identities == {"old", "new"}
ReaderEventKinds == {"none", "advisory", "removal"}

ASSUME /\ Implementation \in {"broken", "current"}
       /\ MaxTime \in Nat
       /\ MaxTime >= 2
       /\ Cutoffs \in SUBSET Times
       /\ Cutoffs # {}

Earliest(values) ==
    CHOOSE candidate \in values : \A other \in values : candidate <= other

(* --algorithm RemoteDeviceRemovalAlgorithm {
variables publishedRemovals = {},
          readerRemovals = {},
          targetRemovals = {},
          publishedAdvisories = {},
          readerAdvisories = {},
          readerSamples = {},
          readerLastOldEvent = "none",
          readerFirstRemovalCutoff = -1,
          targetNotification = FALSE,
          targetPhase = "idle",
          oldRecording = TRUE,
          oldBacklogPresent = TRUE,
          activeIdentity = "old",
          newRecording = FALSE;

define {
    Quiescent ==
        /\ publishedRemovals = Cutoffs
        /\ readerRemovals = Cutoffs
        /\ targetRemovals = Cutoffs
        /\ publishedAdvisories = AdvisoryKinds
        /\ readerAdvisories = AdvisoryKinds
        /\ readerSamples = Times
        /\ targetPhase = "retired"
        /\ activeIdentity = "new"
        /\ newRecording
}

process (CreateRemoval = "CreateRemoval") {
CreateRemovalStep:
    while (TRUE) {
        with (cutoff \in Cutoffs \ publishedRemovals) {
            publishedRemovals := publishedRemovals \cup {cutoff};
        };
    }
}

process (PublishAdvisory = "PublishAdvisory") {
PublishAdvisoryStep:
    while (TRUE) {
        with (kind \in AdvisoryKinds \ publishedAdvisories) {
            publishedAdvisories := publishedAdvisories \cup {kind};
        };
    }
}

process (DeliverRemovalToReader = "DeliverRemovalToReader") {
DeliverRemovalToReaderStep:
    while (TRUE) {
        with (cutoff \in publishedRemovals \ readerRemovals) {
            readerRemovals := readerRemovals \cup {cutoff} ||
            readerLastOldEvent := "removal" ||
            readerFirstRemovalCutoff := IF readerFirstRemovalCutoff = -1
                                            THEN cutoff
                                            ELSE readerFirstRemovalCutoff;
        };
    }
}

process (DeliverRemovalToTarget = "DeliverRemovalToTarget") {
DeliverRemovalToTargetStep:
    while (TRUE) {
        with (cutoff \in publishedRemovals \ targetRemovals) {
            targetRemovals := targetRemovals \cup {cutoff} ||
            targetNotification := IF targetPhase = "retired"
                                      THEN targetNotification
                                      ELSE TRUE;
        };
    }
}

process (DeliverAdvisoryToReader = "DeliverAdvisoryToReader") {
DeliverAdvisoryToReaderStep:
    while (TRUE) {
        with (kind \in publishedAdvisories \ readerAdvisories) {
            readerAdvisories := readerAdvisories \cup {kind} ||
            readerLastOldEvent := "advisory";
        };
    }
}

process (DeliverSampleToReader = "DeliverSampleToReader") {
DeliverSampleToReaderStep:
    while (TRUE) {
        with (timestamp \in Times \ readerSamples) {
            readerSamples := readerSamples \cup {timestamp};
        };
    }
}

fair process (BeginTargetObservation = "BeginTargetObservation") {
BeginTargetObservationStep:
    while (TRUE) {
        await targetPhase = "idle" /\ targetNotification;
        targetPhase := "reading" ||
        targetNotification := FALSE;
    }
}

fair process (ReadTargetSnapshot = "ReadTargetSnapshot") {
ReadTargetSnapshotStep:
    while (TRUE) {
        await targetPhase = "reading" /\ targetRemovals # {};
        targetPhase := "revoking";
    }
}

fair process (RevokeOldRecording = "RevokeOldRecording") {
RevokeOldRecordingStep:
    while (TRUE) {
        await targetPhase = "revoking";
        oldRecording := FALSE ||
        targetPhase := "clearing";
    }
}

fair process (DiscardOldBacklog = "DiscardOldBacklog") {
DiscardOldBacklogStep:
    while (TRUE) {
        await targetPhase = "clearing";
        oldBacklogPresent := FALSE ||
        targetPhase := "retired";
    }
}

process (RejoinWithNewIdentity = "RejoinWithNewIdentity") {
RejoinWithNewIdentityStep:
    while (TRUE) {
        await targetPhase = "retired" /\ activeIdentity = "old";
        activeIdentity := "new" ||
        newRecording := FALSE;
    }
}

process (EnableNewIdentity = "EnableNewIdentity") {
EnableNewIdentityStep:
    while (TRUE) {
        await activeIdentity = "new" /\ ~newRecording;
        newRecording := TRUE;
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
    /\ publishedRemovals \in SUBSET Cutoffs
    /\ readerRemovals \in SUBSET publishedRemovals
    /\ targetRemovals \in SUBSET publishedRemovals
    /\ publishedAdvisories \in SUBSET AdvisoryKinds
    /\ readerAdvisories \in SUBSET publishedAdvisories
    /\ readerSamples \in SUBSET Times
    /\ readerLastOldEvent \in ReaderEventKinds
    /\ readerFirstRemovalCutoff \in {-1} \cup Times
    /\ targetNotification \in BOOLEAN
    /\ targetPhase \in TargetPhases
    /\ oldRecording \in BOOLEAN
    /\ oldBacklogPresent \in BOOLEAN
    /\ activeIdentity \in Identities
    /\ newRecording \in BOOLEAN

EffectiveReaderRemoved ==
    IF Implementation = "current"
        THEN readerRemovals # {}
        ELSE readerLastOldEvent = "removal"

ReaderCutoff ==
    IF readerRemovals = {} THEN 0 ELSE Earliest(readerRemovals)

VisibleOldSamples ==
    IF EffectiveReaderRemoved
        THEN {timestamp \in readerSamples : timestamp < ReaderCutoff}
        ELSE readerSamples

RemovalDominatesAdvisoryState ==
    readerRemovals # {} => EffectiveReaderRemoved

HistoryHonorsEarliestCutoff ==
    readerRemovals # {} =>
        \A timestamp \in VisibleOldSamples : timestamp < Earliest(readerRemovals)

RemovedIdentityNeverRestarts ==
    targetPhase \in {"clearing", "retired"} => ~oldRecording

RejoinCannotReviveRemovedIdentity ==
    activeIdentity = "new" =>
        /\ targetPhase = "retired"
        /\ targetRemovals # {}
        /\ ~oldRecording
        /\ ~oldBacklogPresent

DistinctIdentityRecording ==
    newRecording => activeIdentity = "new" /\ ~oldRecording

DeliveredRemovalEventuallyStops ==
    targetRemovals # {} ~> ~oldRecording

DeliveredRemovalEventuallyRetires ==
    targetRemovals # {} ~> targetPhase = "retired"

CriticalScenarioReached ==
    /\ readerRemovals # {}
    /\ readerLastOldEvent = "advisory"
    /\ \E timestamp \in readerSamples : timestamp >= Earliest(readerRemovals)
    /\ targetPhase = "retired"
    /\ activeIdentity = "new"
    /\ newRecording

CriticalScenarioNotReached == ~CriticalScenarioReached

EarlierCutoffArrivedLate ==
    /\ Cardinality(Cutoffs) > 1
    /\ readerFirstRemovalCutoff > Earliest(Cutoffs)
    /\ readerRemovals = Cutoffs

EarlierCutoffNeverArrivesLate == ~EarlierCutoffArrivedLate

====
