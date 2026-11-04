---- MODULE CompatibilityActivation ----
EXTENDS Integers
CONSTANT Implementation
ASSUME Implementation \in {"current", "no-fence", "volatile-invalidation"}

(* --algorithm CompatibilityActivationAlgorithm {
variables server = 0, cachedMajor = 0, cacheVerified = TRUE,
          permit = 0, activationPending = FALSE, activationFinished = FALSE,
          responseLost = FALSE, refreshResponse = -1, refreshBeforeMutation = FALSE,
          refreshConfirmed = FALSE, retired = FALSE,
          saveStarted = FALSE, invalidationFailed = FALSE;

process (Activation = "activation") {
RetireScope:
    retired := TRUE || permit := -1;
    either {
        invalidationFailed := TRUE;
        activationPending := FALSE || activationFinished := TRUE;
        goto Done;
    } or {
        activationPending := TRUE;
        if (Implementation # "volatile-invalidation") { cacheVerified := FALSE; };
    };
ConditionalServerSave:
    server := 1 || saveStarted := TRUE;
ServerResponse:
    either { responseLost := TRUE; }
    or { cachedMajor := 1; };
Finish:
    activationPending := FALSE || activationFinished := TRUE;
}

process (Refresh = "refresh") {
Begin:
    await ~activationPending \/ Implementation = "no-fence";
    refreshResponse := server;
    refreshBeforeMutation := ~saveStarted;
Receive:
    \* A pre-activation request is superseded by retirement. A request made while the
    \* broken fence is absent can incorrectly restore an older cached grant.
    if (~retired \/ (activationPending /\ Implementation = "no-fence")) {
        cachedMajor := refreshResponse;
        cacheVerified := TRUE;
        permit := refreshResponse;
    } else {
        if (~refreshBeforeMutation /\ ~activationPending) {
            cachedMajor := refreshResponse;
            cacheVerified := TRUE;
            permit := refreshResponse;
            refreshConfirmed := TRUE;
        };
    };
}

process (OfflineRecovery = "offline") {
AfterUncertainOutcome:
    await activationFinished /\ responseLost;
    if (cacheVerified) { permit := cachedMajor; };
}

process (FreshVerification = "fresh") {
VerifyAfterMutation:
    await activationFinished /\ saveStarted;
    cachedMajor := server || cacheVerified := TRUE || permit := server;
    refreshConfirmed := TRUE;
}

process (Stutter = "stutter") {
Again:
    while (TRUE) { skip; }
}
} *)

TypeOK == /\ server \in 0..1 /\ cachedMajor \in 0..1 /\ cacheVerified \in BOOLEAN
          /\ permit \in -1..1 /\ activationPending \in BOOLEAN
          /\ activationFinished \in BOOLEAN /\ responseLost \in BOOLEAN
          /\ refreshResponse \in -1..1 /\ refreshBeforeMutation \in BOOLEAN
          /\ refreshConfirmed \in BOOLEAN /\ retired \in BOOLEAN
          /\ saveStarted \in BOOLEAN /\ invalidationFailed \in BOOLEAN
          /\ pc \in [{"activation", "refresh", "offline", "fresh", "stutter"} ->
              {"RetireScope", "ConditionalServerSave", "ServerResponse",
               "Finish", "Begin", "Receive", "AfterUncertainOutcome", "VerifyAfterMutation", "Again", "Done"}]
NoOldGrantAfterActivation == (activationPending \/ (saveStarted /\ responseLost)) => permit # 0
FailedInvalidationPreventsMutation == invalidationFailed => ~saveStarted
UncertainRecoveryNotReached == ~(responseLost /\ refreshConfirmed /\ permit = 1)
====
