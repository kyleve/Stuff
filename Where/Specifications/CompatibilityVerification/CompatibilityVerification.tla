---- MODULE CompatibilityVerification ----
EXTENDS Integers
CONSTANT Implementation
ASSUME Implementation \in {"current", "local-satisfies-remote", "stale-completion", "local-erases-failure"}

(* --algorithm CompatibilityVerificationAlgorithm {
variables mode = "none", phase = "idle", state = "compatible", captured = "compatible",
          localUsed = FALSE, remoteRequested = FALSE, remotePending = FALSE,
          remoteCompleted = FALSE, remoteRead = FALSE, floor = 1,
          failedVerification = FALSE, remoteSatisfiedLocally = FALSE;

process (LocalHistory = "local") {
LocalStep:
    while (TRUE) {
        await ~localUsed /\ mode = "none";
        localUsed := TRUE;
        if (state # "failed" \/ Implementation = "local-erases-failure") {
            mode := "local" || phase := "read";
        };
    }
}
process (RequestRemote = "request") {
RequestStep:
    while (TRUE) {
        await ~remoteRequested;
        remoteRequested := TRUE || remotePending := TRUE;
    }
}
fair process (StartRemote = "start") {
StartStep:
    while (TRUE) {
        await remotePending /\ mode = "none";
        mode := "remote" || phase := "read";
    }
}
fair process (Read = "read") {
ReadStep:
    while (TRUE) {
        await phase = "read";
        if (mode = "remote") {
            \* The account is unavailable in this scenario. A real authority read must fail.
            remoteRead := TRUE || captured := "failed";
        } else { captured := "compatible"; };
        phase := "complete";
    }
}
fair process (Complete = "complete") {
CompleteStep:
    while (TRUE) {
        await phase = "complete";
        if (state # "update-required" \/ Implementation = "stale-completion") { state := captured; };
        if (mode = "remote") {
            remoteCompleted := TRUE || remotePending := FALSE || failedVerification := TRUE;
        } else if (remotePending /\ Implementation = "local-satisfies-remote") {
            remoteCompleted := TRUE || remotePending := FALSE || remoteSatisfiedLocally := TRUE;
        };
        mode := "none" || phase := "idle";
    }
}
process (ImportRequirement = "import") {
ImportStep:
    while (TRUE) {
        await floor = 1;
        floor := 2 || state := "update-required";
    }
}
process (Stutter = "stutter") { StutterStep: while (TRUE) { skip; } }
} *)

TypeOK == /\ mode \in {"none", "local", "remote"} /\ phase \in {"idle", "read", "complete"}
          /\ state \in {"compatible", "failed", "update-required"} /\ floor \in {1, 2}
RemoteMeansRemote == remoteCompleted => (remoteRead /\ ~remoteSatisfiedLocally)
HigherFloorWins == floor = 2 => state = "update-required"
LocalCannotEraseFailure == failedVerification => state # "compatible"
RemoteEventuallyCompletes == remoteRequested ~> remoteCompleted
JoinedLocalNotReached == ~(remotePending /\ mode = "local")
====
