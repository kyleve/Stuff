---- MODULE RecordingControlSelection ----
EXTENDS FiniteSets, Integers

CONSTANTS Implementation, TimeCount, ReplicaCount
ASSUME /\ Implementation \in {"current", "ignore-explicit", "expire-by-now", "ignore-removal", "global-resume"}
       /\ TimeCount \in {2, 3}
       /\ ReplicaCount \in {1, 2}

Replicas == 1..ReplicaCount
Times == 0..(TimeCount - 1)
Controls == {"source", "automatic", "ignore", "resume", "undo", "shorten", "removal", "opaque"}
IgnoreOperations == {"ignore", "resume", "undo", "shorten"}
Results == {"selected", "removedChoice", "sourceIncomplete", "opaque", "excluded",
            "automaticEligible", "automaticIgnored", "automaticConflict", "automaticIncomplete", "automaticRemoved"}

IgnoreScope(operation) ==
    CASE operation \in {"ignore", "shorten"} -> Times
      [] operation = "resume" -> {TimeCount - 1}
      [] OTHER -> {0}
AppliedScope(operation) ==
    IF Implementation = "global-resume" /\ operation = "resume" THEN Times
    ELSE IgnoreScope(operation)
Parents(operation) == IF operation = "ignore" THEN {} ELSE {"ignore"}
IgnoreAction(operation, instant) ==
    IF operation = "ignore" \/ (operation = "shorten" /\ instant < 1)
    THEN "ignored" ELSE "eligible"
Active(records, instant) == {operation \in records \cap IgnoreOperations : instant \in AppliedScope(operation)}
Heads(records, instant) ==
    {operation \in Active(records, instant) :
        ~\E successor \in Active(records, instant) : operation \in Parents(successor)}
IgnoreResult(records, instant) ==
    IF \E operation \in Active(records, instant) : ~(Parents(operation) \subseteq records)
    THEN "incomplete"
    ELSE LET actions == {IgnoreAction(operation, instant) : operation \in Heads(records, instant)}
         IN IF Cardinality(actions) > 1 THEN "conflict"
            ELSE IF "ignored" \in actions THEN "ignored" ELSE "eligible"

Source(records, instant) ==
    IF "automatic" \in records /\ instant = TimeCount - 1
    THEN IF "source" \in records THEN "automatic" ELSE "incomplete"
    ELSE IF "source" \in records THEN "selected" ELSE "automatic"
Removed(records, instant) == "removal" \in records /\ instant >= 1
Opaque(records, instant) == "opaque" \in records /\ instant = 1

AutomaticResult(records, instant, clock) ==
    IF Removed(records, instant) THEN "automaticRemoved"
    ELSE IF Implementation = "expire-by-now" /\ clock >= TimeCount THEN "automaticEligible"
    ELSE CASE IgnoreResult(records, instant) = "ignored" -> "automaticIgnored"
           [] IgnoreResult(records, instant) = "incomplete" -> "automaticIncomplete"
           [] IgnoreResult(records, instant) = "conflict" -> "automaticConflict"
           [] OTHER -> "automaticEligible"

Resolve(records, instant, clock) ==
    IF Opaque(records, instant) THEN "opaque"
    ELSE IF Source(records, instant) = "incomplete" THEN "sourceIncomplete"
    ELSE IF Source(records, instant) = "selected"
         THEN IF Removed(records, instant) /\ Implementation # "ignore-removal" THEN "removedChoice"
              ELSE IF Implementation = "ignore-explicit" /\ IgnoreResult(records, instant) = "ignored"
                   THEN "excluded" ELSE "selected"
         ELSE AutomaticResult(records, instant, clock)

(* --algorithm RecordingControlSelectionAlgorithm {
variables delivered = [replica \in Replicas |-> {}],
          clock = 0,
          views = [replica \in Replicas |-> [instant \in Times |-> "automaticEligible"]];

process (Delivery \in Replicas) {
Receive:
    while (TRUE) {
        with (control \in Controls) {
            with (next = delivered[self] \cup {control}) {
                delivered[self] := next ||
                views[self] := [instant \in Times |-> Resolve(next, instant, clock)];
            };
        };
    }
}

process (Clock = 0) {
Advance:
    while (TRUE) {
        if (clock < TimeCount) {
            clock := clock + 1 ||
            views := [replica \in Replicas |-> [instant \in Times |-> Resolve(delivered[replica], instant, clock + 1)]];
        } else { skip; };
    }
}
} *)

TypeOK ==
    /\ delivered \in [Replicas -> SUBSET Controls]
    /\ clock \in 0..TimeCount
    /\ views \in [Replicas -> [Times -> Results]]

EqualKnowledgeConverges ==
    \A left, right \in Replicas : delivered[left] = delivered[right] => views[left] = views[right]

ExplicitChoiceBeatsIgnore ==
    \A replica \in Replicas, instant \in Times :
        Source(delivered[replica], instant) = "selected" /\
        ~Removed(delivered[replica], instant) /\ ~Opaque(delivered[replica], instant)
        => views[replica][instant] = "selected"

RemovalPreservesExclusiveChoice ==
    \A replica \in Replicas, instant \in Times :
        Source(delivered[replica], instant) = "selected" /\
        Removed(delivered[replica], instant) /\ ~Opaque(delivered[replica], instant)
        => views[replica][instant] = "removedChoice"

AutomaticRemovalWins ==
    \A replica \in Replicas, instant \in Times :
        Source(delivered[replica], instant) = "automatic" /\
        Removed(delivered[replica], instant) /\ ~Opaque(delivered[replica], instant)
        => views[replica][instant] = "automaticRemoved"

HistoricalIgnoreSurvivesExpiry ==
    \A replica \in Replicas, instant \in Times :
        delivered[replica] \in {{"ignore"}, {"ignore", "source", "automatic"}} /\
        Source(delivered[replica], instant) = "automatic"
        => views[replica][instant] = "automaticIgnored"

ResumePreservesElapsedIgnore ==
    \A replica \in Replicas, instant \in Times :
        delivered[replica] = {"ignore", "resume"}
        => views[replica][instant] = IF instant = TimeCount - 1 THEN "automaticEligible" ELSE "automaticIgnored"

UndoOnlyRestoresItsReviewedPeriod ==
    \A replica \in Replicas, instant \in Times :
        delivered[replica] = {"ignore", "undo"}
        => views[replica][instant] = IF instant = 0 THEN "automaticEligible" ELSE "automaticIgnored"

ShorteningRestoresItsOldTail ==
    \A replica \in Replicas, instant \in Times :
        delivered[replica] = {"ignore", "shorten"}
        => views[replica][instant] = IF instant < 1 THEN "automaticIgnored" ELSE "automaticEligible"

UncertaintyRemainsVisible ==
    \A replica \in Replicas, instant \in Times :
        /\ (Opaque(delivered[replica], instant) => views[replica][instant] = "opaque")
        /\ (~Opaque(delivered[replica], instant) /\ Source(delivered[replica], instant) = "incomplete"
            => views[replica][instant] = "sourceIncomplete")
        /\ (~Opaque(delivered[replica], instant) /\ ~Removed(delivered[replica], instant) /\
            Source(delivered[replica], instant) = "automatic" /\ IgnoreResult(delivered[replica], instant) = "incomplete"
            => views[replica][instant] = "automaticIncomplete")
        /\ (~Opaque(delivered[replica], instant) /\ ~Removed(delivered[replica], instant) /\
            Source(delivered[replica], instant) = "automatic" /\ IgnoreResult(delivered[replica], instant) = "conflict"
            => views[replica][instant] = "automaticConflict")

LateControlScenarioNotReached ==
    ~(clock = TimeCount /\ delivered[1] = {"ignore", "source", "automatic"})
PartialDeliveryScenarioNotReached ==
    ~(delivered[1] = {"source", "shorten"} /\ views[1][0] = "selected")

====
