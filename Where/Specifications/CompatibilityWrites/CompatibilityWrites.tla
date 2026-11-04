---- MODULE CompatibilityWrites ----
EXTENDS Integers

CONSTANT Implementation
ASSUME Implementation \in {"current", "check-only", "reused-permit", "unguarded-read"}

(* --algorithm CompatibilityWritesAlgorithm {
variables oldPermit = TRUE, retired = FALSE, recovered = FALSE,
          pending = FALSE, finished = FALSE, staleCommit = FALSE,
          freshCommit = FALSE, commitLock = FALSE,
          readPending = FALSE, staleRead = FALSE, rejectedWrite = FALSE;

process (OldTransaction = "old") {
Begin:
    await oldPermit;
    pending := TRUE;
AcquireCommit:
    if (oldPermit) {
        commitLock := TRUE;
    } else {
        rejectedWrite := TRUE;
        goto Finish;
    };
PhysicalSave:
    staleCommit := retired;
ReleaseCommit:
    commitLock := FALSE;
Finish:
    pending := FALSE || finished := TRUE;
}

process (Lockout = "lockout") {
Revoke:
    await pending /\ (~commitLock \/ Implementation = "check-only");
    oldPermit := FALSE || retired := TRUE;
}

process (OldRead = "reader") {
StartRead:
    await oldPermit;
    readPending := TRUE;
ValidateReadExit:
    if (oldPermit \/ Implementation = "unguarded-read") {
        staleRead := retired;
    };
    readPending := FALSE;
}

process (Recovery = "recovery") {
FreshScope:
    await retired;
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

process (Stutter = "stutter") {
Again:
    while (TRUE) { skip; }
}
} *)

NoStaleCommit == ~staleCommit
NoStaleRead == ~staleRead
OldScopeStaysRevoked == retired => ~oldPermit
SuspendedWriteRecoveryNotReached == ~(rejectedWrite /\ finished /\ freshCommit)

====
