---- MODULE IngestorQuiesce ----
EXTENDS Integers

CONSTANTS Implementation

ASSUME Implementation \in {"current", "broken"}

Phases == {"idle", "begin", "awaiting", "done"}

VARIABLES
    acceptsSamples,
    isMonitoring,
    inFlightPersist,
    quiescePhase,
    storeCount,
    sampleDelivered,
    postQuiescePersist

vars == <<acceptsSamples, isMonitoring, inFlightPersist, quiescePhase,
          storeCount, sampleDelivered, postQuiescePersist>>

Init ==
    /\ acceptsSamples = TRUE
    /\ isMonitoring = TRUE
    /\ inFlightPersist = FALSE
    /\ quiescePhase = "idle"
    /\ storeCount = 0
    /\ sampleDelivered = FALSE
    /\ postQuiescePersist = FALSE

StreamSample ==
    /\ quiescePhase = "idle"
    /\ ~inFlightPersist
    /\ storeCount < 3
    /\ sampleDelivered' = TRUE
    /\ IF acceptsSamples
          THEN inFlightPersist' = TRUE
          ELSE inFlightPersist' = FALSE
    /\ UNCHANGED <<acceptsSamples, isMonitoring, quiescePhase, storeCount, postQuiescePersist>>

CompletePersist ==
    /\ inFlightPersist
    /\ inFlightPersist' = FALSE
    /\ postQuiescePersist' = (quiescePhase = "done")
    /\ IF quiescePhase = "done" /\ Implementation = "current"
          THEN UNCHANGED storeCount
          ELSE storeCount' = storeCount + 1
    /\ UNCHANGED <<acceptsSamples, isMonitoring, quiescePhase, sampleDelivered>>

BeginQuiesce ==
    /\ quiescePhase = "idle"
    /\ quiescePhase' = "begin"
    /\ acceptsSamples' = IF Implementation = "broken" THEN acceptsSamples ELSE FALSE
    /\ isMonitoring' = FALSE
    /\ UNCHANGED <<inFlightPersist, storeCount, sampleDelivered, postQuiescePersist>>

AwaitInFlight ==
    /\ quiescePhase = "begin"
    /\ quiescePhase' = "awaiting"
    /\ UNCHANGED <<acceptsSamples, isMonitoring, inFlightPersist, storeCount, sampleDelivered, postQuiescePersist>>

CompleteQuiesce ==
    /\ quiescePhase = "awaiting"
    /\ ~inFlightPersist
    /\ quiescePhase' = "done"
    /\ UNCHANGED <<acceptsSamples, isMonitoring, inFlightPersist, storeCount, sampleDelivered, postQuiescePersist>>

LateSampleAfterQuiesce ==
    /\ quiescePhase = "done"
    /\ ~inFlightPersist
    /\ sampleDelivered' = TRUE
    /\ IF acceptsSamples
          THEN inFlightPersist' = TRUE
          ELSE inFlightPersist' = FALSE
    /\ UNCHANGED <<acceptsSamples, isMonitoring, quiescePhase, storeCount, postQuiescePersist>>

Next ==
    \/ StreamSample
    \/ CompletePersist
    \/ BeginQuiesce
    \/ AwaitInFlight
    \/ CompleteQuiesce
    \/ LateSampleAfterQuiesce

Fairness ==
    /\ WF_vars(StreamSample)
    /\ WF_vars(CompletePersist)
    /\ WF_vars(BeginQuiesce)
    /\ WF_vars(AwaitInFlight)
    /\ WF_vars(CompleteQuiesce)
    /\ WF_vars(LateSampleAfterQuiesce)

Spec == Init /\ [][Next]_vars /\ Fairness

TypeOK ==
    /\ acceptsSamples \in BOOLEAN
    /\ isMonitoring \in BOOLEAN
    /\ inFlightPersist \in BOOLEAN
    /\ quiescePhase \in Phases
    /\ storeCount \in 0..3
    /\ sampleDelivered \in BOOLEAN
    /\ postQuiescePersist \in BOOLEAN

NoAcceptAfterQuiesceBegin ==
    quiescePhase \in {"begin", "awaiting", "done"} => ~acceptsSamples

NoPersistAfterQuiesceDone ==
    ~postQuiescePersist

MonitoringOffAtQuiesceDone ==
    quiescePhase = "done" => ~isMonitoring

====
