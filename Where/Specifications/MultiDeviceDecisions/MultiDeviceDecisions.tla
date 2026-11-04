---- MODULE MultiDeviceDecisions ----
EXTENDS FiniteSets, Integers

CONSTANT Implementation
ASSUME Implementation \in {"current", "prefix", "winner", "global"}

Replicas == 1..2
Operations == 1..4
Times == 0..2
Scope(operation) == CASE operation = 1 -> {0, 1}
                     [] operation = 2 -> {1, 2}
                     [] operation = 3 -> {1}
                     [] OTHER -> {2}
Ancestors(operation) == CASE operation \in {1, 2} -> {}
                         [] operation = 3 -> {1, 2}
                         [] OTHER -> {1, 2, 3}
Active(records, instant) == {operation \in records : instant \in Scope(operation)}
Pending(records, instant) ==
    UNION {Ancestors(operation) \ records : operation \in Active(records, instant)}
Maximal(records, instant) ==
    {operation \in Active(records, instant) :
        ~\E successor \in Active(records, instant) : operation \in Ancestors(successor)}
GlobalMaximal(records, instant) ==
    {operation \in Active(records, instant) :
        ~\E successor \in records : operation \in Ancestors(successor)}
Resolve(records, instant) ==
    IF Implementation # "prefix" /\ Pending(records, instant) # {}
    THEN {0}
    ELSE IF Implementation = "winner" /\ Cardinality(Maximal(records, instant)) > 1
         THEN {CHOOSE operation \in Maximal(records, instant) : TRUE}
         ELSE IF Implementation = "global"
              THEN GlobalMaximal(records, instant)
              ELSE Maximal(records, instant)

(* --algorithm MultiDeviceDecisionsAlgorithm {
variables delivered = [replica \in Replicas |-> {}],
          views = [replica \in Replicas |-> [instant \in Times |-> {}]];

process (Deliver \in Replicas) {
Receive:
    while (TRUE) {
        with (operation \in Operations) {
            with (next = delivered[self] \cup {operation}) {
                delivered[self] := next ||
                views[self] := [instant \in Times |-> Resolve(next, instant)];
            };
        };
    }
}
} *)

TypeOK ==
    /\ delivered \in [Replicas -> SUBSET Operations]
    /\ views \in [Replicas -> [Times -> SUBSET (0..4)]]

EqualKnowledgeConverges ==
    delivered[1] = delivered[2] => views[1] = views[2]

MissingDependenciesRemainUnknown ==
    \A replica \in Replicas, instant \in Times :
        Pending(delivered[replica], instant) # {} => views[replica][instant] = {0}

ConcurrentChoicesSurvive ==
    \A replica \in Replicas :
        delivered[replica] = {1, 2} => views[replica][1] = {1, 2}

ReplacementStaysInScope ==
    \A replica \in Replicas :
        1 \in delivered[replica] => views[replica][0] = {1}

CriticalScenarioNotReached ==
    ~(delivered[1] = {3} /\ delivered[2] = {1, 2})

====
