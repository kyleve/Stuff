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

VARIABLES
    publishedRemovals,
    readerRemovals,
    targetRemovals,
    publishedAdvisories,
    readerAdvisories,
    readerSamples,
    readerLastOldEvent,
    readerFirstRemovalCutoff,
    targetNotification,
    targetPhase,
    oldRecording,
    oldBacklogPresent,
    activeIdentity,
    newRecording

vars == <<publishedRemovals, readerRemovals, targetRemovals,
          publishedAdvisories, readerAdvisories, readerSamples,
          readerLastOldEvent, readerFirstRemovalCutoff,
          targetNotification, targetPhase, oldRecording,
          oldBacklogPresent, activeIdentity, newRecording>>

Init ==
    /\ publishedRemovals = {}
    /\ readerRemovals = {}
    /\ targetRemovals = {}
    /\ publishedAdvisories = {}
    /\ readerAdvisories = {}
    /\ readerSamples = {}
    /\ readerLastOldEvent = "none"
    /\ readerFirstRemovalCutoff = -1
    /\ targetNotification = FALSE
    /\ targetPhase = "idle"
    /\ oldRecording = TRUE
    /\ oldBacklogPresent = TRUE
    /\ activeIdentity = "old"
    /\ newRecording = FALSE

CreateRemoval(cutoff) ==
    /\ cutoff \in Cutoffs \ publishedRemovals
    /\ publishedRemovals' = publishedRemovals \cup {cutoff}
    /\ UNCHANGED <<readerRemovals, targetRemovals,
                    publishedAdvisories, readerAdvisories, readerSamples,
                    readerLastOldEvent, readerFirstRemovalCutoff,
                    targetNotification, targetPhase, oldRecording,
                    oldBacklogPresent, activeIdentity, newRecording>>

PublishAdvisory(kind) ==
    /\ kind \in AdvisoryKinds \ publishedAdvisories
    /\ publishedAdvisories' = publishedAdvisories \cup {kind}
    /\ UNCHANGED <<publishedRemovals, readerRemovals, targetRemovals,
                    readerAdvisories, readerSamples, readerLastOldEvent,
                    readerFirstRemovalCutoff, targetNotification, targetPhase,
                    oldRecording, oldBacklogPresent, activeIdentity, newRecording>>

DeliverRemovalToReader(cutoff) ==
    /\ cutoff \in publishedRemovals \ readerRemovals
    /\ readerRemovals' = readerRemovals \cup {cutoff}
    /\ readerLastOldEvent' = "removal"
    /\ readerFirstRemovalCutoff' =
        IF readerFirstRemovalCutoff = -1 THEN cutoff ELSE readerFirstRemovalCutoff
    /\ UNCHANGED <<publishedRemovals, targetRemovals,
                    publishedAdvisories, readerAdvisories, readerSamples,
                    targetNotification, targetPhase, oldRecording,
                    oldBacklogPresent, activeIdentity, newRecording>>

DeliverRemovalToTarget(cutoff) ==
    /\ cutoff \in publishedRemovals \ targetRemovals
    /\ targetRemovals' = targetRemovals \cup {cutoff}
    /\ targetNotification' =
        IF targetPhase = "retired" THEN targetNotification ELSE TRUE
    /\ UNCHANGED <<publishedRemovals, readerRemovals,
                    publishedAdvisories, readerAdvisories, readerSamples,
                    readerLastOldEvent, readerFirstRemovalCutoff, targetPhase,
                    oldRecording, oldBacklogPresent, activeIdentity, newRecording>>

DeliverAdvisoryToReader(kind) ==
    /\ kind \in publishedAdvisories \ readerAdvisories
    /\ readerAdvisories' = readerAdvisories \cup {kind}
    /\ readerLastOldEvent' = "advisory"
    /\ UNCHANGED <<publishedRemovals, readerRemovals, targetRemovals,
                    publishedAdvisories, readerSamples,
                    readerFirstRemovalCutoff, targetNotification, targetPhase,
                    oldRecording, oldBacklogPresent, activeIdentity, newRecording>>

DeliverSampleToReader(timestamp) ==
    /\ timestamp \in Times \ readerSamples
    /\ readerSamples' = readerSamples \cup {timestamp}
    /\ UNCHANGED <<publishedRemovals, readerRemovals, targetRemovals,
                    publishedAdvisories, readerAdvisories, readerLastOldEvent,
                    readerFirstRemovalCutoff, targetNotification, targetPhase,
                    oldRecording, oldBacklogPresent, activeIdentity, newRecording>>

BeginTargetObservation ==
    /\ targetPhase = "idle"
    /\ targetNotification
    /\ targetPhase' = "reading"
    /\ targetNotification' = FALSE
    /\ UNCHANGED <<publishedRemovals, readerRemovals, targetRemovals,
                    publishedAdvisories, readerAdvisories, readerSamples,
                    readerLastOldEvent, readerFirstRemovalCutoff,
                    oldRecording, oldBacklogPresent, activeIdentity, newRecording>>

ReadTargetSnapshot ==
    /\ targetPhase = "reading"
    /\ targetRemovals # {}
    /\ targetPhase' = "revoking"
    /\ UNCHANGED <<publishedRemovals, readerRemovals, targetRemovals,
                    publishedAdvisories, readerAdvisories, readerSamples,
                    readerLastOldEvent, readerFirstRemovalCutoff,
                    targetNotification, oldRecording, oldBacklogPresent,
                    activeIdentity, newRecording>>

RevokeOldRecording ==
    /\ targetPhase = "revoking"
    /\ oldRecording' = FALSE
    /\ targetPhase' = "clearing"
    /\ UNCHANGED <<publishedRemovals, readerRemovals, targetRemovals,
                    publishedAdvisories, readerAdvisories, readerSamples,
                    readerLastOldEvent, readerFirstRemovalCutoff,
                    targetNotification, oldBacklogPresent,
                    activeIdentity, newRecording>>

DiscardOldBacklog ==
    /\ targetPhase = "clearing"
    /\ oldBacklogPresent' = FALSE
    /\ targetPhase' = "retired"
    /\ UNCHANGED <<publishedRemovals, readerRemovals, targetRemovals,
                    publishedAdvisories, readerAdvisories, readerSamples,
                    readerLastOldEvent, readerFirstRemovalCutoff,
                    targetNotification, oldRecording, activeIdentity, newRecording>>

RejoinWithNewIdentity ==
    /\ targetPhase = "retired"
    /\ activeIdentity = "old"
    /\ activeIdentity' = "new"
    /\ newRecording' = FALSE
    /\ UNCHANGED <<publishedRemovals, readerRemovals, targetRemovals,
                    publishedAdvisories, readerAdvisories, readerSamples,
                    readerLastOldEvent, readerFirstRemovalCutoff,
                    targetNotification, targetPhase, oldRecording,
                    oldBacklogPresent>>

EnableNewIdentity ==
    /\ activeIdentity = "new"
    /\ ~newRecording
    /\ newRecording' = TRUE
    /\ UNCHANGED <<publishedRemovals, readerRemovals, targetRemovals,
                    publishedAdvisories, readerAdvisories, readerSamples,
                    readerLastOldEvent, readerFirstRemovalCutoff,
                    targetNotification, targetPhase, oldRecording,
                    oldBacklogPresent, activeIdentity>>

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

Done ==
    /\ Quiescent
    /\ UNCHANGED vars

Next ==
    \/ \E cutoff \in Cutoffs :
          CreateRemoval(cutoff)
          \/ DeliverRemovalToReader(cutoff)
          \/ DeliverRemovalToTarget(cutoff)
    \/ \E kind \in AdvisoryKinds :
          PublishAdvisory(kind)
          \/ DeliverAdvisoryToReader(kind)
    \/ \E timestamp \in Times : DeliverSampleToReader(timestamp)
    \/ BeginTargetObservation
    \/ ReadTargetSnapshot
    \/ RevokeOldRecording
    \/ DiscardOldBacklog
    \/ RejoinWithNewIdentity
    \/ EnableNewIdentity
    \/ Done

Fairness ==
    /\ WF_vars(BeginTargetObservation)
    /\ WF_vars(ReadTargetSnapshot)
    /\ WF_vars(RevokeOldRecording)
    /\ WF_vars(DiscardOldBacklog)

Spec == Init /\ [][Next]_vars /\ Fairness

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
