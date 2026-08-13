---- MODULE StorePerformSerialization ----
EXTENDS Integers

CONSTANTS Implementation

ASSUME Implementation \in {"current", "broken"}

TaskPhases == {"idle", "waiting", "inPerform", "committed"}

(* --algorithm StorePerformSerializationAlgorithm {
variables isTransacting = FALSE,
          waiterCount = 0,
          taskAPhase = "idle",
          taskBPhase = "idle",
          nestedDepth = 0,
          aCommitted = FALSE,
          bCommitted = FALSE;

fair process (BeginOuterA = "BeginOuterA") {
BeginOuterAStep:
    while (TRUE) {
        await taskAPhase = "idle";
        if (isTransacting) {
            taskAPhase := "waiting" ||
            waiterCount := waiterCount + 1;
        } else {
            taskAPhase := "inPerform" ||
            isTransacting := TRUE;
        };
    }
}

fair process (BeginOuterB = "BeginOuterB") {
BeginOuterBStep:
    while (TRUE) {
        await taskBPhase = "idle";
        if (Implementation = "broken" /\ taskAPhase = "inPerform") {
            taskBPhase := "inPerform";
        } else if (isTransacting) {
            taskBPhase := "waiting" ||
            waiterCount := waiterCount + 1;
        } else {
            taskBPhase := "inPerform" ||
            isTransacting := TRUE;
        };
    }
}

fair process (BeginNestedSameTask = "BeginNestedSameTask") {
BeginNestedSameTaskStep:
    while (TRUE) {
        await taskAPhase = "inPerform" /\ nestedDepth < 1;
        nestedDepth := nestedDepth + 1;
    }
}

fair process (CommitA = "CommitA") {
CommitAStep:
    while (TRUE) {
        await taskAPhase = "inPerform" /\ nestedDepth = 0;
        if (waiterCount > 0) {
            taskAPhase := "committed" ||
            aCommitted := TRUE ||
            waiterCount := waiterCount - 1 ||
            taskBPhase := "inPerform";
        } else {
            taskAPhase := "committed" ||
            aCommitted := TRUE ||
            isTransacting := FALSE;
        };
    }
}

fair process (CommitB = "CommitB") {
CommitBStep:
    while (TRUE) {
        await taskBPhase = "inPerform";
        if (waiterCount > 0) {
            taskBPhase := "committed" ||
            bCommitted := TRUE ||
            waiterCount := waiterCount - 1 ||
            taskAPhase := "inPerform";
        } else {
            taskBPhase := "committed" ||
            bCommitted := TRUE ||
            isTransacting := FALSE;
        };
    }
}

fair process (EndNested = "EndNested") {
EndNestedStep:
    while (TRUE) {
        await nestedDepth > 0;
        nestedDepth := nestedDepth - 1;
    }
}
} *)

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
