---- MODULE CompatibilityOutputs ----
EXTENDS Integers
CONSTANT Implementation
ASSUME Implementation \in {"current", "no-drain", "accept-retired"}

(* --algorithm CompatibilityOutputsAlgorithm {
variables revoked = FALSE, queueClosed = FALSE, queued = FALSE, completed = FALSE,
          output = "initial", withdrawn = FALSE, replacementPublished = FALSE;

process (OldPublisher = "old") {
Enqueue:
    if (queueClosed /\ Implementation # "accept-retired") { goto Done; }
    else { queued := TRUE; };
BeginSystemCall:
    if (revoked /\ Implementation # "accept-retired") { goto Finish; };
SystemAccepts:
    \* The system can finish a submitted call after revocation. Caller cancellation
    \* does not cancel or remove this operation from the queue's owned task chain.
    output := "old";
Finish:
    completed := TRUE;
}

process (Retirement = "retire") {
Revoke:
    revoked := TRUE;
CloseQueue:
    queueClosed := TRUE;
Drain:
    await ~queued \/ completed \/ Implementation = "no-drain";
Withdraw:
    output := "empty" || withdrawn := TRUE;
}

process (Replacement = "replacement") {
WaitForRetirement:
    await withdrawn;
Publish:
    output := "replacement" || replacementPublished := TRUE;
}

process (Stutter = "stutter") {
Again:
    while (TRUE) { skip; }
}
} *)

TypeOK == /\ revoked \in BOOLEAN /\ queueClosed \in BOOLEAN
          /\ queued \in BOOLEAN /\ completed \in BOOLEAN
          /\ output \in {"initial", "old", "empty", "replacement"}
          /\ withdrawn \in BOOLEAN /\ replacementPublished \in BOOLEAN
          /\ pc \in [{"old", "retire", "replacement", "stutter"} ->
              {"Enqueue", "BeginSystemCall", "SystemAccepts", "Finish", "Revoke",
               "CloseQueue", "Drain", "Withdraw", "WaitForRetirement", "Publish", "Again", "Done"}]
NoObsoleteOutput == withdrawn => output # "old"
ReplacementSurvives == replacementPublished => output = "replacement"
RecoveryNotReached == ~replacementPublished
====
