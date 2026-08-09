---- MODULE PostWriteReconcile ----
EXTENDS Integers

CONSTANTS Implementation

ASSUME Implementation \in {"current", "broken"}

WritePhases == {"idle", "inPerform", "committed"}
ReconcilePhases == {"none", "invalidating", "reminders", "widgets", "done"}

VARIABLES
    writePhase,
    reconcilePhase,
    changesPinged,
    sideEffectsApplied,
    readerSawPing

vars == <<writePhase, reconcilePhase, changesPinged, sideEffectsApplied, readerSawPing>>

Init ==
    /\ writePhase = "idle"
    /\ reconcilePhase = "none"
    /\ changesPinged = FALSE
    /\ sideEffectsApplied = FALSE
    /\ readerSawPing = FALSE

BeginPerform ==
    /\ writePhase = "idle"
    /\ writePhase' = "inPerform"
    /\ UNCHANGED <<reconcilePhase, changesPinged, sideEffectsApplied, readerSawPing>>

Commit ==
    /\ writePhase = "inPerform"
    /\ writePhase' = "committed"
    /\ reconcilePhase' = "invalidating"
    /\ UNCHANGED <<changesPinged, sideEffectsApplied, readerSawPing>>

StepInvalidate ==
    /\ reconcilePhase = "invalidating"
    /\ reconcilePhase' = "reminders"
    /\ UNCHANGED <<writePhase, changesPinged, sideEffectsApplied, readerSawPing>>

StepReminders ==
    /\ reconcilePhase = "reminders"
    /\ reconcilePhase' = "widgets"
    /\ UNCHANGED <<writePhase, changesPinged, sideEffectsApplied, readerSawPing>>

StepWidgets ==
    /\ reconcilePhase = "widgets"
    /\ reconcilePhase' = "done"
    /\ sideEffectsApplied' = TRUE
    /\ UNCHANGED <<writePhase, changesPinged, readerSawPing>>

PingChanges ==
    /\ writePhase = "committed"
    /\ IF Implementation = "broken"
          THEN TRUE
          ELSE reconcilePhase = "done"
    /\ changesPinged' = TRUE
    /\ UNCHANGED <<writePhase, reconcilePhase, sideEffectsApplied, readerSawPing>>

ReaderRefresh ==
    /\ changesPinged
    /\ readerSawPing' = TRUE
    /\ UNCHANGED <<writePhase, reconcilePhase, changesPinged, sideEffectsApplied>>

ResetPath ==
    /\ writePhase = "committed"
    /\ writePhase' = "idle"
    /\ reconcilePhase' = "none"
    /\ changesPinged' = FALSE
    /\ sideEffectsApplied' = FALSE
    /\ readerSawPing' = FALSE

Next ==
    \/ BeginPerform
    \/ Commit
    \/ StepInvalidate
    \/ StepReminders
    \/ StepWidgets
    \/ PingChanges
    \/ ReaderRefresh
    \/ ResetPath

Fairness ==
    /\ WF_vars(BeginPerform)
    /\ WF_vars(Commit)
    /\ WF_vars(StepInvalidate)
    /\ WF_vars(StepReminders)
    /\ WF_vars(StepWidgets)
    /\ WF_vars(PingChanges)
    /\ WF_vars(ReaderRefresh)
    /\ WF_vars(ResetPath)

Spec == Init /\ [][Next]_vars /\ Fairness

TypeOK ==
    /\ writePhase \in WritePhases
    /\ reconcilePhase \in ReconcilePhases
    /\ changesPinged \in BOOLEAN
    /\ sideEffectsApplied \in BOOLEAN
    /\ readerSawPing \in BOOLEAN

NoChangesBeforeReconcileDone ==
    (Implementation = "current") =>
        (changesPinged => reconcilePhase = "done")

BrokenNoEarlyPing ==
    changesPinged => reconcilePhase = "done"

ReaderSeesAppliedSideEffects ==
    readerSawPing => sideEffectsApplied

====
