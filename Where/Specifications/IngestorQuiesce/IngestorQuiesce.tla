---- MODULE IngestorQuiesce ----
EXTENDS Integers

CONSTANTS Implementation

ASSUME Implementation \in {"current", "broken"}

Phases == {"idle", "begin", "awaiting", "done"}

(* --algorithm IngestorQuiesceAlgorithm {
variables acceptsSamples = TRUE,
          isMonitoring = TRUE,
          inFlightPersist = FALSE,
          quiescePhase = "idle",
          storeCount = 0,
          sampleDelivered = FALSE,
          postQuiescePersist = FALSE;

fair process (StreamSample = "StreamSample") {
StreamSampleStep:
    while (TRUE) {
        await quiescePhase = "idle" /\ ~inFlightPersist /\ storeCount < 3;
        sampleDelivered := TRUE ||
        inFlightPersist := IF acceptsSamples THEN TRUE ELSE FALSE;
    }
}

fair process (CompletePersist = "CompletePersist") {
CompletePersistStep:
    while (TRUE) {
        await inFlightPersist;
        inFlightPersist := FALSE ||
        postQuiescePersist := (quiescePhase = "done") ||
        storeCount := IF quiescePhase = "done" /\ Implementation = "current"
                          THEN storeCount
                          ELSE storeCount + 1;
    }
}

fair process (BeginQuiesce = "BeginQuiesce") {
BeginQuiesceStep:
    while (TRUE) {
        await quiescePhase = "idle";
        quiescePhase := "begin" ||
        acceptsSamples := IF Implementation = "broken" THEN acceptsSamples ELSE FALSE ||
        isMonitoring := FALSE;
    }
}

fair process (AwaitInFlight = "AwaitInFlight") {
AwaitInFlightStep:
    while (TRUE) {
        await quiescePhase = "begin";
        quiescePhase := "awaiting";
    }
}

fair process (CompleteQuiesce = "CompleteQuiesce") {
CompleteQuiesceStep:
    while (TRUE) {
        await quiescePhase = "awaiting" /\ ~inFlightPersist;
        quiescePhase := "done";
    }
}

fair process (LateSampleAfterQuiesce = "LateSampleAfterQuiesce") {
LateSampleAfterQuiesceStep:
    while (TRUE) {
        await quiescePhase = "done" /\ ~inFlightPersist;
        sampleDelivered := TRUE ||
        inFlightPersist := IF acceptsSamples THEN TRUE ELSE FALSE;
    }
}
} *)

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
