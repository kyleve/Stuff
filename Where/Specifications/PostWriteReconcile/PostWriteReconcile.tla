---- MODULE PostWriteReconcile ----
EXTENDS Integers

CONSTANTS Implementation

ASSUME Implementation \in {"current", "broken"}

WritePhases == {"idle", "inPerform", "committed"}
ReconcilePhases == {"none", "invalidating", "reminders", "widgets", "done"}

(* --algorithm PostWriteReconcileAlgorithm {
variables writePhase = "idle",
          reconcilePhase = "none",
          changesPinged = FALSE,
          sideEffectsApplied = FALSE,
          readerSawPing = FALSE;

fair process (BeginPerform = "BeginPerform") {
BeginPerformStep:
    while (TRUE) {
        await writePhase = "idle";
        writePhase := "inPerform";
    }
}

fair process (Commit = "Commit") {
CommitStep:
    while (TRUE) {
        await writePhase = "inPerform";
        writePhase := "committed" ||
        reconcilePhase := "invalidating";
    }
}

fair process (StepInvalidate = "StepInvalidate") {
StepInvalidateStep:
    while (TRUE) {
        await reconcilePhase = "invalidating";
        reconcilePhase := "reminders";
    }
}

fair process (StepReminders = "StepReminders") {
StepRemindersStep:
    while (TRUE) {
        await reconcilePhase = "reminders";
        reconcilePhase := "widgets";
    }
}

fair process (StepWidgets = "StepWidgets") {
StepWidgetsStep:
    while (TRUE) {
        await reconcilePhase = "widgets";
        reconcilePhase := "done" ||
        sideEffectsApplied := TRUE;
    }
}

fair process (PingChanges = "PingChanges") {
PingChangesStep:
    while (TRUE) {
        await writePhase = "committed" /\
              (IF Implementation = "broken" THEN TRUE ELSE reconcilePhase = "done");
        changesPinged := TRUE;
    }
}

fair process (ReaderRefresh = "ReaderRefresh") {
ReaderRefreshStep:
    while (TRUE) {
        await changesPinged;
        readerSawPing := TRUE;
    }
}

fair process (ResetPath = "ResetPath") {
ResetPathStep:
    while (TRUE) {
        await writePhase = "committed";
        writePhase := "idle" ||
        reconcilePhase := "none" ||
        changesPinged := FALSE ||
        sideEffectsApplied := FALSE ||
        readerSawPing := FALSE;
    }
}
} *)

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
