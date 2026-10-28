---- MODULE CompatibilityWrites ----
EXTENDS Integers
CONSTANT Implementation
ASSUME Implementation \in {"current", "missing-commit-check", "reused-permit"}

(* --algorithm CompatibilityWritesAlgorithm {
variables oldPermit = TRUE, blocked = FALSE, recovered = FALSE,
          pending = FALSE, finished = FALSE, staleCommit = FALSE,
          freshCommit = FALSE;

process (OldTransaction = "old") {
Begin:
    await oldPermit /\ ~blocked;
    pending := TRUE;
Commit:
    if (oldPermit \/ Implementation = "missing-commit-check") {
        staleCommit := blocked;
    };
    pending := FALSE || finished := TRUE;
}
process (Lockout = "lockout") {
Revoke:
    await pending;
    oldPermit := FALSE || blocked := TRUE;
}
process (Recovery = "recovery") {
FreshScope:
    await blocked;
    recovered := TRUE;
    if (Implementation = "reused-permit") { oldPermit := TRUE; };
FreshTransaction:
    freshCommit := TRUE;
}
process (LateOldCaller = "late") {
TryOldScope:
    await recovered /\ finished;
    if (oldPermit) { staleCommit := TRUE; };
}
process (Stutter = "stutter") { Again: while (TRUE) { skip; } }
} *)

NoStaleCommit == ~staleCommit
OldScopeStaysRevoked == blocked => ~oldPermit
RecoveryNotReached == ~(finished /\ freshCommit /\ ~staleCommit)
====
