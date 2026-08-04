---- MODULE TrackingReconciliation ----
EXTENDS Integers, Sequences

CONSTANTS Implementation, Commands, Authorized

ASSUME /\ Implementation \in {"broken", "coalesced"}
       /\ Commands \in Seq(BOOLEAN)
       /\ Len(Commands) > 0
       /\ Authorized \in BOOLEAN

CommandIDs == 1..Len(Commands)
Phases == {"unsubmitted", "queued", "preparing", "starting", "stopping", "done"}
WorkerStates == {"idle", "ready", "starting", "stopping"}

VARIABLES
    submitted,
    desired,
    persisted,
    ingestorActive,
    published,
    taskPhase,
    worker,
    target

vars == <<submitted, desired, persisted, ingestorActive, published,
          taskPhase, worker, target>>

Init ==
    /\ submitted = 0
    /\ desired = FALSE
    /\ persisted = FALSE
    /\ ingestorActive = FALSE
    /\ published = FALSE
    /\ taskPhase = [i \in CommandIDs |-> "unsubmitted"]
    /\ worker = "idle"
    /\ target = FALSE

Submit ==
    /\ submitted < Len(Commands)
    /\ LET i == submitted + 1
           value == Commands[i]
       IN /\ submitted' = i
          /\ desired' = value
          /\ IF Implementation = "broken"
                THEN /\ taskPhase' = [taskPhase EXCEPT ![i] = "queued"]
                     /\ UNCHANGED <<persisted, worker>>
                ELSE /\ taskPhase' = taskPhase
                     /\ persisted' = value
                     /\ worker' = IF worker = "idle" THEN "ready" ELSE worker
          /\ UNCHANGED <<ingestorActive, published, target>>

BrokenBegin(i) ==
    /\ Implementation = "broken"
    /\ taskPhase[i] = "queued"
    /\ persisted' = Commands[i]
    /\ taskPhase' = [taskPhase EXCEPT
                        ![i] = IF Commands[i] THEN "preparing" ELSE "stopping"]
    /\ ingestorActive' = IF Commands[i] THEN ingestorActive ELSE FALSE
    /\ UNCHANGED <<submitted, desired, published, worker, target>>

BrokenReconcile(i) ==
    /\ Implementation = "broken"
    /\ taskPhase[i] = "preparing"
    /\ taskPhase' = [taskPhase EXCEPT
                        ![i] = IF persisted /\ Authorized
                                THEN "starting"
                                ELSE "stopping"]
    /\ ingestorActive' = persisted /\ Authorized
    /\ UNCHANGED <<submitted, desired, persisted, published, worker, target>>

BrokenCompleteStart(i) ==
    /\ Implementation = "broken"
    /\ taskPhase[i] = "starting"
    /\ published' = TRUE
    /\ taskPhase' = [taskPhase EXCEPT ![i] = "done"]
    /\ UNCHANGED <<submitted, desired, persisted, ingestorActive, worker, target>>

BrokenCompleteStop(i) ==
    /\ Implementation = "broken"
    /\ taskPhase[i] = "stopping"
    /\ published' = FALSE
    /\ taskPhase' = [taskPhase EXCEPT ![i] = "done"]
    /\ UNCHANGED <<submitted, desired, persisted, ingestorActive, worker, target>>

FixedBegin ==
    /\ Implementation = "coalesced"
    /\ worker = "ready"
    /\ target' = desired /\ Authorized
    /\ worker' = IF target' THEN "starting" ELSE "stopping"
    /\ ingestorActive' = target'
    /\ UNCHANGED <<submitted, desired, persisted, published, taskPhase>>

FixedCompleteStart ==
    /\ Implementation = "coalesced"
    /\ worker = "starting"
    /\ published' = TRUE
    /\ worker' = IF desired /\ Authorized = target THEN "idle" ELSE "ready"
    /\ UNCHANGED <<submitted, desired, persisted, ingestorActive, taskPhase, target>>

FixedCompleteStop ==
    /\ Implementation = "coalesced"
    /\ worker = "stopping"
    /\ published' = FALSE
    /\ worker' = IF (desired /\ Authorized) = target THEN "idle" ELSE "ready"
    /\ UNCHANGED <<submitted, desired, persisted, ingestorActive, taskPhase, target>>

Next ==
    \/ Submit
    \/ \E i \in CommandIDs :
          BrokenBegin(i) \/ BrokenReconcile(i)
          \/ BrokenCompleteStart(i) \/ BrokenCompleteStop(i)
    \/ FixedBegin
    \/ FixedCompleteStart
    \/ FixedCompleteStop

Fairness ==
    /\ WF_vars(Submit)
    /\ \A i \in CommandIDs :
          /\ WF_vars(BrokenBegin(i))
          /\ WF_vars(BrokenReconcile(i))
          /\ WF_vars(BrokenCompleteStart(i))
          /\ WF_vars(BrokenCompleteStop(i))
    /\ WF_vars(FixedBegin)
    /\ WF_vars(FixedCompleteStart)
    /\ WF_vars(FixedCompleteStop)

Spec == Init /\ [][Next]_vars /\ Fairness

DesiredEffective == desired /\ Authorized

Quiescent ==
    /\ submitted = Len(Commands)
    /\ IF Implementation = "broken"
          THEN \A i \in CommandIDs : taskPhase[i] = "done"
          ELSE worker = "idle"

TypeOK ==
    /\ submitted \in 0..Len(Commands)
    /\ desired \in BOOLEAN
    /\ persisted \in BOOLEAN
    /\ ingestorActive \in BOOLEAN
    /\ published \in BOOLEAN
    /\ taskPhase \in [CommandIDs -> Phases]
    /\ worker \in WorkerStates
    /\ target \in BOOLEAN

FixedIntentIsImmediate ==
    Implementation = "coalesced" => persisted = desired

CorrectAtQuiescence ==
    Quiescent =>
        /\ persisted = desired
        /\ ingestorActive = DesiredEffective
        /\ published = DesiredEffective

EventuallySettled ==
    submitted = Len(Commands) ~>
        (Quiescent /\ persisted = desired
                   /\ ingestorActive = DesiredEffective
                   /\ published = DesiredEffective)

EnableThenDisable == <<TRUE, FALSE>>

====
