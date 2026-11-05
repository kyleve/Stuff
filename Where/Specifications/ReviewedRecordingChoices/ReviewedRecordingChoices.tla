---- MODULE ReviewedRecordingChoices ----
EXTENDS Integers, FiniteSets

CONSTANT Implementation, MaxAttempts
ASSUME Implementation \in {"current", "adopt-newer", "ignore-evidence", "new-retry-id", "rebind-generation"}
ASSUME MaxAttempts \in {2, 3}

(* --algorithm ReviewedRecordingChoicesAlgorithm {
variables prepared = FALSE, evidence = 0, decisions = {"base"}, history = 0,
          generation = 0, permit = TRUE, commitLock = FALSE,
          operationID = "reviewed", attempts = 0, readEvidence = 0,
          readDecisions = {"base"}, readHistory = 0,
          stagedPredecessors = {"base"}, stored = {}, outcome = "pending",
          lostResponse = FALSE, retriedImport = FALSE;

process (Writer = "writer") {
Preview:
    prepared := TRUE;
Begin:
    attempts := attempts + 1;
    if (~permit) { outcome := "revoked"; goto Finish; }
    else {
        if (generation # 0) { outcome := "stale"; goto Finish; }
        else {
            if (\E record \in stored: record.id = operationID) {
                outcome := "applied"; goto Finish;
            };
        };
    };
ReadSnapshot:
    readEvidence := evidence || readDecisions := decisions || readHistory := history;
CompareReview:
    if ((readEvidence # 0 /\ Implementation # "ignore-evidence") \/
        (readDecisions # {"base"} /\ Implementation # "adopt-newer")) {
        outcome := "stale"; goto Finish;
    };
Stage:
    stagedPredecessors := IF Implementation = "adopt-newer" THEN readDecisions ELSE {"base"};
CommitGuard:
    if (~permit) { outcome := "revoked"; goto Finish; }
    else {
        if (readHistory # history) {
            if (attempts < MaxAttempts) {
                retriedImport := TRUE;
                goto Begin;
            } else { outcome := "busy"; goto Finish; };
        } else { commitLock := TRUE; };
    };
PhysicalSave:
    stored := stored \cup {[id |-> operationID, predecessors |-> stagedPredecessors,
                           checkedEvidence |-> readEvidence,
                           dataGeneration |-> IF Implementation = "rebind-generation" THEN generation ELSE 0]};
ReleaseCommit:
    commitLock := FALSE;
ReceiveOutcome:
    either { outcome := "applied"; goto Finish; }
    or {
        if (~lostResponse /\ attempts < MaxAttempts) {
            lostResponse := TRUE;
            if (Implementation = "new-retry-id") { operationID := "replacement"; };
            goto Begin;
        } else { outcome := "applied"; goto Finish; };
    };
Finish:
    skip;
}

process (SampleImport = "sample") {
DeliverSample:
    await prepared;
    evidence := 1 || history := history + 1;
}

process (DecisionImport = "decision") {
DeliverDecision:
    await prepared;
    decisions := decisions \cup {"remote"} || history := history + 1;
}

process (UnrelatedImport = "unrelated") {
DeliverUnrelated:
    await prepared;
    history := history + 1;
}

process (Reset = "reset") {
RotateGeneration:
    await prepared;
    generation := 1 || history := history + 1;
}

process (Retirement = "retirement") {
Revoke:
    await prepared /\ ~commitLock;
    permit := FALSE;
}

process (Stutter = "stutter") {
Again:
    while (TRUE) { skip; }
}
} *)

TypeOK == /\ prepared \in BOOLEAN /\ evidence \in 0..1
          /\ decisions \subseteq {"base", "remote"} /\ history \in 0..4
          /\ generation \in 0..1 /\ permit \in BOOLEAN /\ commitLock \in BOOLEAN
          /\ operationID \in {"reviewed", "replacement"} /\ attempts \in 0..MaxAttempts
          /\ readEvidence \in 0..1 /\ readDecisions \subseteq {"base", "remote"}
          /\ readHistory \in 0..4 /\ stagedPredecessors \subseteq {"base", "remote"}
          /\ stored \subseteq [id: {"reviewed", "replacement"},
                                predecessors: SUBSET {"base", "remote"},
                                checkedEvidence: 0..1, dataGeneration: 0..1]
          /\ outcome \in {"pending", "applied", "stale", "revoked", "busy"}
          /\ lostResponse \in BOOLEAN /\ retriedImport \in BOOLEAN
          /\ pc \in [{"writer", "sample", "decision", "unrelated", "reset", "retirement", "stutter"} ->
              {"Preview", "Begin", "ReadSnapshot", "CompareReview", "Stage", "CommitGuard",
               "PhysicalSave", "ReleaseCommit", "ReceiveOutcome", "Finish", "DeliverSample",
               "DeliverDecision", "DeliverUnrelated", "RotateGeneration", "Revoke", "Again", "Done"}]

OnlyReviewedPredecessors == \A record \in stored: record.predecessors = {"base"}
KnownChangedEvidenceRequiresReview == \A record \in stored: record.checkedEvidence = 0
RetryRetainsIdentity == operationID = "reviewed"
NoGenerationRebinding == \A record \in stored: record.dataGeneration = 0
RetrySuccessNotReached == ~(retriedImport /\ outcome = "applied" /\ stored # {})
LostResponseRecoveryNotReached == ~(lostResponse /\ outcome = "applied" /\ stored # {})
ChangedReviewNotReached == ~(outcome = "stale" /\ stored = {} /\ evidence = 1)

====
