---- MODULE TrackingReconciliation ----
EXTENDS Integers, Sequences

CONSTANTS Implementation, Commands, Authorized

ASSUME /\ Implementation \in {"broken", "current"}
       /\ Commands \in Seq(BOOLEAN)
       /\ Len(Commands) > 0
       /\ Authorized \in BOOLEAN

CommandIDs == 1..Len(Commands)
Phases == {"unsubmitted", "queued", "preparing", "starting", "stopping",
           "permission", "waiting", "transitioning", "done"}

(* --algorithm TrackingReconciliationAlgorithm {
variables submitted = 0,
          desired = FALSE,
          persisted = FALSE,
          controllerChoice = FALSE,
          ingestorActive = FALSE,
          published = FALSE,
          taskPhase = [i \in CommandIDs |-> "unsubmitted"],
          queue = <<>>,
          inFlight = 0,
          target = FALSE,
          staleRejected = FALSE;

define {
    Quiescent ==
        /\ submitted = Len(Commands)
        /\ \A i \in CommandIDs : taskPhase[i] = "done"
        /\ IF Implementation = "current"
              THEN /\ queue = <<>>
                   /\ inFlight = 0
              ELSE TRUE

    DesiredEffective == desired /\ Authorized
}

fair process (Submit = <<"Submit", 0>>) {
SubmitStep:
    while (TRUE) {
        await submitted < Len(Commands);
        with (i = submitted + 1) {
            with (value = Commands[i]) {
                if (Implementation = "broken") {
                    submitted := i ||
                    desired := value ||
                    taskPhase[i] := "queued";
                } else if (value) {
                    submitted := i ||
                    desired := value ||
                    persisted := value ||
                    taskPhase[i] := "permission";
                } else {
                    submitted := i ||
                    desired := value ||
                    persisted := value ||
                    taskPhase[i] := "waiting" ||
                    queue := Append(queue, i);
                };
            };
        };
    }
}

fair process (BrokenBegin \in {<<"BrokenBegin", i>> : i \in CommandIDs}) {
BrokenBeginStep:
    while (TRUE) {
        await Implementation = "broken" /\ taskPhase[self[2]] = "queued";
        persisted := Commands[self[2]] ||
        controllerChoice := Commands[self[2]] ||
        taskPhase[self[2]] := IF Commands[self[2]] THEN "preparing" ELSE "stopping" ||
        ingestorActive := IF Commands[self[2]] THEN ingestorActive ELSE FALSE;
    }
}

fair process (BrokenReconcile \in {<<"BrokenReconcile", i>> : i \in CommandIDs}) {
BrokenReconcileStep:
    while (TRUE) {
        await Implementation = "broken" /\ taskPhase[self[2]] = "preparing";
        taskPhase[self[2]] := IF persisted /\ Authorized THEN "starting" ELSE "stopping" ||
        controllerChoice := persisted ||
        ingestorActive := persisted /\ Authorized;
    }
}

fair process (BrokenCompleteStart \in {<<"BrokenCompleteStart", i>> : i \in CommandIDs}) {
BrokenCompleteStartStep:
    while (TRUE) {
        await Implementation = "broken" /\ taskPhase[self[2]] = "starting";
        published := TRUE ||
        taskPhase[self[2]] := "done";
    }
}

fair process (BrokenCompleteStop \in {<<"BrokenCompleteStop", i>> : i \in CommandIDs}) {
BrokenCompleteStopStep:
    while (TRUE) {
        await Implementation = "broken" /\ taskPhase[self[2]] = "stopping";
        published := FALSE ||
        taskPhase[self[2]] := "done";
    }
}

fair process (CurrentPermissionComplete \in
              {<<"CurrentPermissionComplete", i>> : i \in CommandIDs}) {
CurrentPermissionCompleteStep:
    while (TRUE) {
        await Implementation = "current" /\ taskPhase[self[2]] = "permission";
        if (self[2] = submitted) {
            taskPhase[self[2]] := "waiting" ||
            queue := Append(queue, self[2]);
        } else {
            taskPhase[self[2]] := "done" ||
            staleRejected := TRUE;
        };
    }
}

fair process (CurrentBegin = <<"CurrentBegin", 0>>) {
CurrentBeginStep:
    while (TRUE) {
        await Implementation = "current" /\ inFlight = 0 /\ Len(queue) > 0;
        with (i = Head(queue)) {
            await taskPhase[i] = "waiting";
            queue := Tail(queue) ||
            inFlight := i ||
            taskPhase[i] := "transitioning" ||
            controllerChoice := Commands[i] ||
            target := Commands[i] /\ Authorized ||
            ingestorActive := Commands[i] /\ Authorized;
        };
    }
}

fair process (CurrentComplete = <<"CurrentComplete", 0>>) {
CurrentCompleteStep:
    while (TRUE) {
        await Implementation = "current" /\ inFlight \in CommandIDs /\
              taskPhase[inFlight] = "transitioning";
        published := target ||
        taskPhase[inFlight] := "done" ||
        inFlight := 0;
    }
}

process (Done = <<"Done", 0>>) {
DoneStep:
    while (TRUE) {
        await Quiescent;
        skip;
    }
}
} *)

TypeOK ==
    /\ submitted \in 0..Len(Commands)
    /\ desired \in BOOLEAN
    /\ persisted \in BOOLEAN
    /\ controllerChoice \in BOOLEAN
    /\ ingestorActive \in BOOLEAN
    /\ published \in BOOLEAN
    /\ taskPhase \in [CommandIDs -> Phases]
    /\ queue \in Seq(CommandIDs)
    /\ inFlight \in 0..Len(Commands)
    /\ target \in BOOLEAN
    /\ staleRejected \in BOOLEAN

CurrentIntentIsImmediate ==
    Implementation = "current" => persisted = desired

CorrectAtQuiescence ==
    Quiescent =>
        /\ persisted = desired
        /\ controllerChoice = desired
        /\ ingestorActive = DesiredEffective
        /\ published = DesiredEffective

EventuallySettled ==
    submitted = Len(Commands) ~>
        (Quiescent /\ persisted = desired
                   /\ controllerChoice = desired
                   /\ ingestorActive = DesiredEffective
                   /\ published = DesiredEffective)

StalePermissionNotObserved == ~staleRejected

EnableThenDisable == <<TRUE, FALSE>>
DisableThenEnable == <<FALSE, TRUE>>
EnableEnableDisable == <<TRUE, TRUE, FALSE>>

====
