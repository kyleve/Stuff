---- MODULE CompatibilityVerification ----
EXTENDS Integers
CONSTANT Implementation
ASSUME Implementation \in {"current", "skip-remote-read", "stale-completion", "local-unblocks"}

(* --algorithm CompatibilityVerificationAlgorithm {
variables phase = "idle", state = "waiting", captured = "waiting",
          localUsed = FALSE, remoteRequested = FALSE, remoteCompleted = FALSE,
          remoteRead = FALSE, floor = 1, localDuringRemote = FALSE;

process (LocalHistory = "local") {
LocalStep:
    while (TRUE) {
        await ~localUsed;
        localUsed := TRUE;
        if (phase # "idle") { localDuringRemote := TRUE; };
        if (floor = 2) { state := "update-required"; }
        else if (Implementation = "local-unblocks") { state := "compatible"; };
    }
}
process (RequestRemote = "request") {
RequestStep:
    while (TRUE) {
        await ~remoteRequested;
        remoteRequested := TRUE || phase := "read";
    }
}
fair process (Read = "read") {
ReadStep:
    while (TRUE) {
        await phase = "read";
        remoteRead := Implementation # "skip-remote-read";
        either { captured := "compatible"; } or { captured := "failed"; };
        phase := "complete";
    }
}
fair process (Complete = "complete") {
CompleteStep:
    while (TRUE) {
        await phase = "complete";
        if (state # "update-required" \/ Implementation = "stale-completion") {
            state := captured;
        };
        remoteCompleted := TRUE || phase := "idle";
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

TypeOK == /\ phase \in {"idle", "read", "complete"}
          /\ state \in {"waiting", "compatible", "failed", "update-required"}
          /\ captured \in {"waiting", "compatible", "failed"} /\ floor \in {1, 2}
RemoteMeansRemote == remoteCompleted => remoteRead
HigherFloorWins == floor = 2 => state = "update-required"
OnlyVerificationUnblocks == state = "compatible" => (remoteCompleted /\ captured = "compatible")
RemoteEventuallyCompletes == remoteRequested ~> remoteCompleted
LocalDuringRemoteNotReached == ~localDuringRemote
====
