---- MODULE LaunchLifecycle ----
EXTENDS Integers

CONSTANTS Implementation

ASSUME Implementation \in {"current", "broken"}

Reasons == {"undetermined", "userForeground"}
Phases == {"notStarted", "driving", "ready"}

(* --algorithm LaunchLifecycleAlgorithm {
variables reason = "undetermined",
          phase = "notStarted",
          driveActive = FALSE,
          memoSyncAuth = FALSE,
          memoReconcile = FALSE,
          captureTodayDone = FALSE,
          syncAuthRuns = 0,
          reconcileRuns = 0;

fair process (StartDrive = "StartDrive") {
StartDriveStep:
    while (TRUE) {
        await phase = "notStarted";
        phase := "driving" ||
        driveActive := TRUE;
    }
}

fair process (RunSyncAuth = "RunSyncAuth") {
RunSyncAuthStep:
    while (TRUE) {
        await phase = "driving" /\ driveActive /\
              (IF Implementation = "current" THEN memoSyncAuth = FALSE ELSE TRUE);
        memoSyncAuth := TRUE ||
        syncAuthRuns := syncAuthRuns + 1;
    }
}

fair process (RunReconcileTracking = "RunReconcileTracking") {
RunReconcileTrackingStep:
    while (TRUE) {
        await phase = "driving" /\ driveActive /\
              (IF Implementation = "current" THEN memoReconcile = FALSE ELSE TRUE);
        memoReconcile := TRUE ||
        reconcileRuns := reconcileRuns + 1;
    }
}

fair process (RunCaptureToday = "RunCaptureToday") {
RunCaptureTodayStep:
    while (TRUE) {
        await phase = "driving" /\ driveActive /\
              reason = "userForeground" /\ ~captureTodayDone;
        captureTodayDone := TRUE;
    }
}

fair process (EnterForeground = "EnterForeground") {
EnterForegroundStep:
    while (TRUE) {
        await reason = "undetermined" /\ phase \in {"driving", "ready"};
        reason := "userForeground" ||
        phase := "driving" ||
        driveActive := TRUE ||
        memoSyncAuth := IF Implementation = "broken" THEN FALSE ELSE memoSyncAuth ||
        memoReconcile := IF Implementation = "broken" THEN FALSE ELSE memoReconcile;
    }
}

fair process (ReachReady = "ReachReady") {
ReachReadyStep:
    while (TRUE) {
        await phase = "driving" /\ driveActive /\ memoSyncAuth /\ memoReconcile /\
              (reason = "undetermined" \/ captureTodayDone);
        phase := "ready" ||
        driveActive := FALSE;
    }
}

process (Stutter = "Stutter") {
StutterStep:
    while (TRUE) {
        await phase = "ready";
        skip;
    }
}
} *)

TypeOK ==
    /\ reason \in Reasons
    /\ phase \in Phases
    /\ driveActive \in BOOLEAN
    /\ memoSyncAuth \in BOOLEAN
    /\ memoReconcile \in BOOLEAN
    /\ captureTodayDone \in BOOLEAN
    /\ syncAuthRuns \in 0..4
    /\ reconcileRuns \in 0..4

SingleDrive ==
    ~driveActive \/ phase \in {"driving", "ready"}

MemoNoDoubleRun ==
    /\ syncAuthRuns <= 1
    /\ reconcileRuns <= 1

UndeterminedNoCaptureToday ==
    reason = "undetermined" => ~captureTodayDone

ForegroundCaptureBeforeReady ==
    phase = "ready" /\ reason = "userForeground" => captureTodayDone

====
