---- MODULE LaunchLifecycle ----
EXTENDS Integers

CONSTANTS Implementation

ASSUME Implementation \in {"current", "broken"}

Reasons == {"undetermined", "userForeground"}
Phases == {"notStarted", "driving", "ready"}

VARIABLES
    reason,
    phase,
    driveActive,
    memoSyncAuth,
    memoReconcile,
    captureTodayDone,
    syncAuthRuns,
    reconcileRuns

vars == <<reason, phase, driveActive, memoSyncAuth, memoReconcile,
          captureTodayDone, syncAuthRuns, reconcileRuns>>

Init ==
    /\ reason = "undetermined"
    /\ phase = "notStarted"
    /\ driveActive = FALSE
    /\ memoSyncAuth = FALSE
    /\ memoReconcile = FALSE
    /\ captureTodayDone = FALSE
    /\ syncAuthRuns = 0
    /\ reconcileRuns = 0

StartDrive ==
    /\ phase = "notStarted"
    /\ phase' = "driving"
    /\ driveActive' = TRUE
    /\ UNCHANGED <<reason, memoSyncAuth, memoReconcile, captureTodayDone,
                   syncAuthRuns, reconcileRuns>>

RunSyncAuth ==
    /\ phase = "driving"
    /\ driveActive
    /\ IF Implementation = "current"
          THEN memoSyncAuth = FALSE
          ELSE TRUE
    /\ memoSyncAuth' = TRUE
    /\ syncAuthRuns' = syncAuthRuns + 1
    /\ UNCHANGED <<reason, phase, driveActive, memoReconcile, captureTodayDone,
                   reconcileRuns>>

RunReconcileTracking ==
    /\ phase = "driving"
    /\ driveActive
    /\ IF Implementation = "current"
          THEN memoReconcile = FALSE
          ELSE TRUE
    /\ memoReconcile' = TRUE
    /\ reconcileRuns' = reconcileRuns + 1
    /\ UNCHANGED <<reason, phase, driveActive, memoSyncAuth, captureTodayDone,
                   syncAuthRuns>>

RunCaptureToday ==
    /\ phase = "driving"
    /\ driveActive
    /\ reason = "userForeground"
    /\ ~captureTodayDone
    /\ captureTodayDone' = TRUE
    /\ UNCHANGED <<reason, phase, driveActive, memoSyncAuth, memoReconcile,
                   syncAuthRuns, reconcileRuns>>

EnterForeground ==
    /\ reason = "undetermined"
    /\ phase \in {"driving", "ready"}
    /\ reason' = "userForeground"
    /\ phase' = "driving"
    /\ driveActive' = TRUE
    /\ IF Implementation = "broken"
          THEN /\ memoSyncAuth' = FALSE
               /\ memoReconcile' = FALSE
          ELSE UNCHANGED <<memoSyncAuth, memoReconcile>>
    /\ UNCHANGED <<captureTodayDone, syncAuthRuns, reconcileRuns>>

ReachReady ==
    /\ phase = "driving"
    /\ driveActive
    /\ memoSyncAuth
    /\ memoReconcile
    /\ (reason = "undetermined" \/ captureTodayDone)
    /\ phase' = "ready"
    /\ driveActive' = FALSE
    /\ UNCHANGED <<reason, memoSyncAuth, memoReconcile, captureTodayDone,
                   syncAuthRuns, reconcileRuns>>

Stutter ==
    phase = "ready"
    /\ UNCHANGED vars

Next ==
    \/ StartDrive
    \/ RunSyncAuth
    \/ RunReconcileTracking
    \/ RunCaptureToday
    \/ EnterForeground
    \/ ReachReady
    \/ Stutter

Fairness ==
    /\ WF_vars(StartDrive)
    /\ WF_vars(RunSyncAuth)
    /\ WF_vars(RunReconcileTracking)
    /\ WF_vars(RunCaptureToday)
    /\ WF_vars(EnterForeground)
    /\ WF_vars(ReachReady)

Spec == Init /\ [][Next]_vars /\ Fairness

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
