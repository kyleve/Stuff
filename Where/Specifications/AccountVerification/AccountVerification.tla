---- MODULE AccountVerification ----
EXTENDS Integers
CONSTANT Implementation
ASSUME Implementation \in {"current", "stale-response", "cached-after-change", "forget-restart", "accept-other-account"}

(* --algorithm AccountVerificationAlgorithm {
variables epoch = 0, account = "A", access = TRUE, grantedEpoch = 0,
          verified = TRUE, invalidated = FALSE, changed = FALSE,
          capturedEpoch = 0, pending = FALSE, completed = FALSE,
          restarted = FALSE, retried = FALSE, cached = FALSE,
          staleProjection = FALSE;

process (OldRequest = "old") {
Capture:
    await ~changed;
    capturedEpoch := epoch || pending := TRUE;
Complete:
    if (capturedEpoch = epoch \/ Implementation = "stale-response") {
        access := TRUE || grantedEpoch := capturedEpoch;
        if (capturedEpoch # epoch) { staleProjection := TRUE; };
    };
    pending := FALSE || completed := TRUE;
}
process (AccountChange = "change") {
Invalidate:
    await pending;
    epoch := 1 || changed := TRUE || access := FALSE || verified := FALSE || invalidated := TRUE;
    either { account := "A"; } or { account := "B"; };
}
process (Restart = "restart") {
RestartProcess:
    await changed;
    restarted := TRUE || access := FALSE;
    if (Implementation = "forget-restart") {
        invalidated := FALSE || verified := TRUE;
    } else { verified := FALSE; };
}
process (OfflineRetry = "offline") {
Fallback:
    await changed;
    cached := TRUE;
    if ((verified /\ ~invalidated) \/ Implementation = "cached-after-change") {
        access := TRUE || grantedEpoch := epoch;
    };
}
process (OnlineRetry = "online") {
VerifyCurrent:
    await changed /\ completed;
    retried := TRUE;
    if (account = "A" \/ Implementation = "accept-other-account") {
        invalidated := FALSE || verified := TRUE || access := TRUE || grantedEpoch := epoch;
    };
}
process (Stutter = "stutter") { StutterStep: while (TRUE) { skip; } }
} *)

TypeOK == /\ epoch \in {0, 1} /\ grantedEpoch \in {0, 1}
          /\ account \in {"A", "B"}
NoOldAccountAccess == access => (grantedEpoch = epoch /\ account = "A" /\ ~invalidated)
NoStaleProjection == ~staleProjection
RestartNeedsVerification == (restarted /\ ~retried) => ~access
RaceNotReached == ~(changed /\ pending)
RecoveryNotReached == ~(changed /\ retried /\ access /\ account = "A")
====
