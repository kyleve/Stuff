---- MODULE AutomaticBackupLifecycle ----
EXTENDS Integers, FiniteSets

CONSTANTS Implementation, MaxRuns
ASSUME /\ Implementation \in {"candidate", "review-ui", "review-unlock", "broken-drain", "broken-generation"}
       /\ MaxRuns \in 1..2

Runs == 1..MaxRuns
Stages == {"unused", "key", "snapshot", "staging", "writing", "committed", "success", "done"}

(* --algorithm AutomaticBackupLifecycleAlgorithm {
variables unlocked = FALSE,
          context = "unloaded",
          earlyContextRead = FALSE,
          availability = "active",
          generation = 0,
          enabled = TRUE,
          disabledOnce = FALSE,
          admitted = 0,
          active = 0,
          stage = [r \in Runs |-> "unused"],
          runGeneration = [r \in Runs |-> 0],
          cancelled = {},
          committed = {},
          successful = {},
          published = 0,
          uiJoined = 0,
          uiDismissed = FALSE,
          accidentalCancellation = FALSE,
          expired = FALSE,
          lateWrite = FALSE,
          sawInFlightRetirement = FALSE;

fair process (Unlock = "unlock") {
UnlockStep:
    while (TRUE) {
        await ~unlocked;
        unlocked := TRUE;
    }
}
fair process (LoadContext = "context") {
LoadContextStep:
    while (TRUE) {
        await context = "unloaded" /\ (unlocked \/ Implementation = "review-unlock");
        context := IF unlocked THEN "ready" ELSE "failed" ||
        earlyContextRead := ~unlocked;
    }
}
process (AdmitOrJoin = "admit") {
AdmitOrJoinStep:
    while (TRUE) {
        await unlocked /\ context = "ready" /\ availability = "active" /\ enabled;
        if (active = 0) {
            await admitted < MaxRuns;
            active := admitted + 1 ||
            admitted := admitted + 1 ||
            stage[admitted + 1] := "key" ||
            runGeneration[admitted + 1] := generation;
        } else {
            await uiJoined = 0 /\ ~uiDismissed;
            uiJoined := active;
        };
    }
}
process (DismissUI = "dismiss") {
DismissUIStep:
    while (TRUE) {
        await uiJoined # 0 /\ ~uiDismissed;
        uiDismissed := TRUE;
        if (Implementation = "review-ui" /\ stage[uiJoined] # "done") {
            cancelled := cancelled \cup {uiJoined} ||
            accidentalCancellation := TRUE;
        };
    }
}
process (Disable = "disable") {
DisableStep:
    while (TRUE) {
        await ~disabledOnce;
        enabled := FALSE || disabledOnce := TRUE ||
        cancelled := IF active # 0 THEN cancelled \cup {active} ELSE cancelled;
    }
}
process (Expire = "expire") {
ExpireStep:
    while (TRUE) {
        await active # 0 /\ ~expired;
        expired := TRUE || cancelled := cancelled \cup {active};
    }
}
fair process (Prepare = "prepare") {
PrepareStep:
    while (TRUE) {
        with (r \in Runs) {
            await stage[r] \in {"key", "snapshot", "staging"};
            stage[r] := IF r \in cancelled THEN "done"
                        ELSE CASE stage[r] = "key" -> "snapshot"
                               [] stage[r] = "snapshot" -> "staging"
                               [] OTHER -> "writing";
        };
    }
}
fair process (Write = "write") {
WriteStep:
    while (TRUE) {
        with (r \in Runs) {
            await stage[r] = "writing";
            either {
                stage[r] := "committed" || committed := committed \cup {r} ||
                lateWrite := lateWrite \/ availability = "retired";
            } or {
                stage[r] := "done";
            };
        };
    }
}
fair process (RecordSuccess = "success") {
RecordSuccessStep:
    while (TRUE) {
        with (r \in Runs) {
            await stage[r] = "committed";
            stage[r] := IF r \in cancelled THEN "done" ELSE "success" ||
            successful := IF r \in cancelled THEN successful ELSE successful \cup {r};
        };
    }
}
fair process (FinishMaintenance = "maintenance") {
FinishMaintenanceStep:
    while (TRUE) {
        with (r \in Runs) {
            await stage[r] = "success";
            \* Success and failure of maintenance both preserve the committed result.
            stage[r] := "done";
        };
    }
}
fair process (ReleaseRun = "release") {
ReleaseRunStep:
    while (TRUE) {
        await active # 0 /\ stage[active] = "done";
        active := 0;
    }
}
process (PublishPreference = "publish") {
PublishPreferenceStep:
    while (TRUE) {
        with (r \in successful) {
            await stage[r] = "done";
            if (runGeneration[r] = generation \/ Implementation = "broken-generation") {
                published := r;
            };
        };
    }
}
process (BeginRetirement = "retire") {
BeginRetirementStep:
    while (TRUE) {
        await availability = "active";
        availability := "closing" ||
        sawInFlightRetirement := active # 0 ||
        cancelled := IF active # 0 THEN cancelled \cup {active} ELSE cancelled;
    }
}
fair process (Drain = "drain") {
DrainStep:
    while (TRUE) {
        await availability = "closing" /\ (active = 0 \/ Implementation = "broken-drain");
        availability := "retired" || generation := 1 || published := 0;
    }
}
process (Idle = "idle") {
IdleStep:
    while (TRUE) { skip; }
}
} *)

TypeOK ==
    /\ unlocked \in BOOLEAN /\ earlyContextRead \in BOOLEAN
    /\ context \in {"unloaded", "failed", "ready"}
    /\ availability \in {"active", "closing", "retired"}
    /\ generation \in 0..1 /\ enabled \in BOOLEAN /\ disabledOnce \in BOOLEAN
    /\ admitted \in 0..MaxRuns /\ active \in 0..MaxRuns
    /\ stage \in [Runs -> Stages] /\ runGeneration \in [Runs -> 0..1]
    /\ cancelled \subseteq Runs /\ committed \subseteq Runs /\ successful \subseteq Runs
    /\ published \in 0..MaxRuns /\ uiJoined \in 0..MaxRuns
    /\ uiDismissed \in BOOLEAN /\ accidentalCancellation \in BOOLEAN
    /\ expired \in BOOLEAN /\ lateWrite \in BOOLEAN /\ sawInFlightRetirement \in BOOLEAN
NoEarlyContextRead == ~earlyContextRead
UIHasNoCancellationAuthority == ~accidentalCancellation
SingleFlight == Cardinality({r \in Runs : stage[r] \notin {"unused", "done"}}) <= 1
NoWriteAfterRetirement == ~lateWrite
SuccessRequiresCommit == successful \subseteq committed
NoStalePreference == published = 0 \/ runGeneration[published] = generation
RetirementDrained == availability = "retired" => \A r \in Runs : stage[r] \in {"unused", "done"}
EventuallyReady == <> (context = "ready")
EventuallyDrained == (availability = "closing") ~> (availability = "retired")
CriticalStateNotReached == ~(sawInFlightRetirement /\ availability = "retired" /\ committed # {})
====
