---- MODULE StorePerformSerialization ----
EXTENDS Integers

CONSTANTS Implementation

ASSUME Implementation \in {"current", "broken"}

TaskPhases == {"idle", "waiting", "inPerform", "committed"}

VARIABLES
    isTransacting,
    waiterCount,
    taskAPhase,
    taskBPhase,
    nestedDepth,
    aCommitted,
    bCommitted

vars == <<isTransacting, waiterCount, taskAPhase, taskBPhase, nestedDepth,
          aCommitted, bCommitted>>

Init ==
    /\ isTransacting = FALSE
    /\ waiterCount = 0
    /\ taskAPhase = "idle"
    /\ taskBPhase = "idle"
    /\ nestedDepth = 0
    /\ aCommitted = FALSE
    /\ bCommitted = FALSE

BeginOuterA ==
    /\ taskAPhase = "idle"
    /\ IF isTransacting
          THEN /\ taskAPhase' = "waiting"
               /\ waiterCount' = waiterCount + 1
               /\ UNCHANGED <<isTransacting, taskBPhase, nestedDepth, aCommitted, bCommitted>>
          ELSE /\ taskAPhase' = "inPerform"
               /\ isTransacting' = TRUE
               /\ UNCHANGED <<waiterCount, taskBPhase, nestedDepth, aCommitted, bCommitted>>

BeginOuterB ==
    /\ taskBPhase = "idle"
    /\ IF /\ Implementation = "broken"
          /\ taskAPhase = "inPerform"
          THEN /\ taskBPhase' = "inPerform"
               /\ UNCHANGED <<isTransacting, waiterCount, taskAPhase, nestedDepth, aCommitted, bCommitted>>
          ELSE IF isTransacting
                  THEN /\ taskBPhase' = "waiting"
                       /\ waiterCount' = waiterCount + 1
                       /\ UNCHANGED <<isTransacting, taskAPhase, nestedDepth, aCommitted, bCommitted>>
                  ELSE /\ taskBPhase' = "inPerform"
                       /\ isTransacting' = TRUE
                       /\ UNCHANGED <<waiterCount, taskAPhase, nestedDepth, aCommitted, bCommitted>>

BeginNestedSameTask ==
    /\ taskAPhase = "inPerform"
    /\ nestedDepth < 1
    /\ nestedDepth' = nestedDepth + 1
    /\ UNCHANGED <<isTransacting, waiterCount, taskAPhase, taskBPhase, aCommitted, bCommitted>>

CommitA ==
    /\ taskAPhase = "inPerform"
    /\ nestedDepth = 0
    /\ taskAPhase' = "committed"
    /\ aCommitted' = TRUE
    /\ IF waiterCount > 0
          THEN /\ waiterCount' = waiterCount - 1
               /\ taskBPhase' = "inPerform"
               /\ UNCHANGED isTransacting
          ELSE /\ isTransacting' = FALSE
               /\ UNCHANGED <<waiterCount, taskBPhase>>
    /\ UNCHANGED <<nestedDepth, bCommitted>>

CommitB ==
    /\ taskBPhase = "inPerform"
    /\ taskBPhase' = "committed"
    /\ bCommitted' = TRUE
    /\ IF waiterCount > 0
          THEN /\ waiterCount' = waiterCount - 1
               /\ taskAPhase' = "inPerform"
               /\ UNCHANGED isTransacting
          ELSE /\ isTransacting' = FALSE
               /\ UNCHANGED <<waiterCount, taskAPhase>>
    /\ UNCHANGED <<nestedDepth, aCommitted>>

EndNested ==
    /\ nestedDepth > 0
    /\ nestedDepth' = nestedDepth - 1
    /\ UNCHANGED <<isTransacting, waiterCount, taskAPhase, taskBPhase, aCommitted, bCommitted>>

Next ==
    \/ BeginOuterA
    \/ BeginOuterB
    \/ BeginNestedSameTask
    \/ CommitA
    \/ CommitB
    \/ EndNested

Fairness ==
    /\ WF_vars(BeginOuterA)
    /\ WF_vars(BeginOuterB)
    /\ WF_vars(BeginNestedSameTask)
    /\ WF_vars(CommitA)
    /\ WF_vars(CommitB)
    /\ WF_vars(EndNested)

Spec == Init /\ [][Next]_vars /\ Fairness

TypeOK ==
    /\ isTransacting \in BOOLEAN
    /\ waiterCount \in 0..2
    /\ taskAPhase \in TaskPhases
    /\ taskBPhase \in TaskPhases
    /\ nestedDepth \in 0..1
    /\ aCommitted \in BOOLEAN
    /\ bCommitted \in BOOLEAN

AtMostOneOutermost ==
    (taskAPhase = "inPerform" /\ nestedDepth = 0) =>
        taskBPhase \notin {"inPerform"}

NestedSameTaskNoWait ==
    nestedDepth > 0 => taskAPhase = "inPerform"

AllCommit ==
    aCommitted /\ bCommitted

====
