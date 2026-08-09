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

VARIABLES
    submitted,
    desired,
    persisted,
    controllerChoice,
    ingestorActive,
    published,
    taskPhase,
    queue,
    inFlight,
    target,
    staleRejected

vars == <<submitted, desired, persisted, controllerChoice, ingestorActive,
          published, taskPhase, queue, inFlight, target, staleRejected>>

Init ==
    /\ submitted = 0
    /\ desired = FALSE
    /\ persisted = FALSE
    /\ controllerChoice = FALSE
    /\ ingestorActive = FALSE
    /\ published = FALSE
    /\ taskPhase = [i \in CommandIDs |-> "unsubmitted"]
    /\ queue = <<>>
    /\ inFlight = 0
    /\ target = FALSE
    /\ staleRejected = FALSE

Submit ==
    /\ submitted < Len(Commands)
    /\ LET i == submitted + 1
           value == Commands[i]
       IN /\ submitted' = i
          /\ desired' = value
          /\ IF Implementation = "broken"
                THEN /\ taskPhase' = [taskPhase EXCEPT ![i] = "queued"]
                     /\ UNCHANGED <<persisted, queue>>
                ELSE /\ persisted' = value
                     /\ IF value
                           THEN /\ taskPhase' = [taskPhase EXCEPT ![i] = "permission"]
                                /\ queue' = queue
                           ELSE /\ taskPhase' = [taskPhase EXCEPT ![i] = "waiting"]
                                /\ queue' = Append(queue, i)
          /\ UNCHANGED <<controllerChoice, ingestorActive, published, inFlight,
                         target, staleRejected>>

BrokenBegin(i) ==
    /\ Implementation = "broken"
    /\ taskPhase[i] = "queued"
    /\ persisted' = Commands[i]
    /\ controllerChoice' = Commands[i]
    /\ taskPhase' = [taskPhase EXCEPT
                        ![i] = IF Commands[i] THEN "preparing" ELSE "stopping"]
    /\ ingestorActive' = IF Commands[i] THEN ingestorActive ELSE FALSE
    /\ UNCHANGED <<submitted, desired, published, queue, inFlight, target,
                    staleRejected>>

BrokenReconcile(i) ==
    /\ Implementation = "broken"
    /\ taskPhase[i] = "preparing"
    /\ taskPhase' = [taskPhase EXCEPT
                        ![i] = IF persisted /\ Authorized
                                THEN "starting"
                                ELSE "stopping"]
    /\ controllerChoice' = persisted
    /\ ingestorActive' = persisted /\ Authorized
    /\ UNCHANGED <<submitted, desired, persisted, published, queue, inFlight,
                    target, staleRejected>>

BrokenCompleteStart(i) ==
    /\ Implementation = "broken"
    /\ taskPhase[i] = "starting"
    /\ published' = TRUE
    /\ taskPhase' = [taskPhase EXCEPT ![i] = "done"]
    /\ UNCHANGED <<submitted, desired, persisted, controllerChoice,
                    ingestorActive, queue, inFlight, target, staleRejected>>

BrokenCompleteStop(i) ==
    /\ Implementation = "broken"
    /\ taskPhase[i] = "stopping"
    /\ published' = FALSE
    /\ taskPhase' = [taskPhase EXCEPT ![i] = "done"]
    /\ UNCHANGED <<submitted, desired, persisted, controllerChoice,
                    ingestorActive, queue, inFlight, target, staleRejected>>

CurrentPermissionComplete(i) ==
    /\ Implementation = "current"
    /\ taskPhase[i] = "permission"
    /\ IF i = submitted
          THEN /\ taskPhase' = [taskPhase EXCEPT ![i] = "waiting"]
               /\ queue' = Append(queue, i)
               /\ staleRejected' = staleRejected
          ELSE /\ taskPhase' = [taskPhase EXCEPT ![i] = "done"]
               /\ queue' = queue
               /\ staleRejected' = TRUE
    /\ UNCHANGED <<submitted, desired, persisted, controllerChoice,
                    ingestorActive, published, inFlight, target>>

CurrentBegin ==
    /\ Implementation = "current"
    /\ inFlight = 0
    /\ Len(queue) > 0
    /\ LET i == Head(queue)
           effective == Commands[i] /\ Authorized
       IN /\ taskPhase[i] = "waiting"
          /\ queue' = Tail(queue)
          /\ inFlight' = i
          /\ taskPhase' = [taskPhase EXCEPT ![i] = "transitioning"]
          /\ controllerChoice' = Commands[i]
          /\ target' = effective
          /\ ingestorActive' = effective
    /\ UNCHANGED <<submitted, desired, persisted, published, staleRejected>>

CurrentComplete ==
    /\ Implementation = "current"
    /\ inFlight \in CommandIDs
    /\ taskPhase[inFlight] = "transitioning"
    /\ published' = target
    /\ taskPhase' = [taskPhase EXCEPT ![inFlight] = "done"]
    /\ inFlight' = 0
    /\ UNCHANGED <<submitted, desired, persisted, controllerChoice,
                    ingestorActive, queue, target, staleRejected>>

Quiescent ==
    /\ submitted = Len(Commands)
    /\ \A i \in CommandIDs : taskPhase[i] = "done"
    /\ IF Implementation = "current"
          THEN /\ queue = <<>>
               /\ inFlight = 0
          ELSE TRUE

Done ==
    /\ Quiescent
    /\ UNCHANGED vars

Next ==
    \/ Submit
    \/ \E i \in CommandIDs :
          BrokenBegin(i) \/ BrokenReconcile(i)
          \/ BrokenCompleteStart(i) \/ BrokenCompleteStop(i)
          \/ CurrentPermissionComplete(i)
    \/ CurrentBegin
    \/ CurrentComplete
    \/ Done

Fairness ==
    /\ WF_vars(Submit)
    /\ \A i \in CommandIDs :
          /\ WF_vars(BrokenBegin(i))
          /\ WF_vars(BrokenReconcile(i))
          /\ WF_vars(BrokenCompleteStart(i))
          /\ WF_vars(BrokenCompleteStop(i))
          /\ WF_vars(CurrentPermissionComplete(i))
    /\ WF_vars(CurrentBegin)
    /\ WF_vars(CurrentComplete)

Spec == Init /\ [][Next]_vars /\ Fairness

DesiredEffective == desired /\ Authorized

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
