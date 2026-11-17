---- MODULE CompatibilityLockout ----
EXTENDS Integers, FiniteSets

CONSTANTS Implementation, MaxChecks, MaxScopes, MaxAccountChanges

ASSUME /\ Implementation \in {"current", "ungatedOpen", "uncheckedVerification", "uncheckedOpening", "uncheckedScopeEpoch",
                              "revivableGPS", "lateGPS", "earlyRelaunch", "retainedTask", "lateRetirement"}
       /\ MaxChecks > 0 /\ MaxScopes > 0 /\ MaxAccountChanges > 0

Checks == 1..MaxChecks
Scopes == 1..MaxScopes
Tasks == 1..(MaxChecks + MaxAccountChanges)
ScopePhases == {"unused", "opening", "active", "discarding", "released"}
GPSPhases == {"idle", "authorizing", "starting", "returning", "cleanup", "done"}

(* --algorithm CompatibilityLockoutAlgorithm {
variables accountEpoch = 0,
          decision = "checking", decisionEpoch = 0,
          checks = 0, currentCheck = 0,
          checkPhase = [i \in Checks |-> "unused"],
          checkEpoch = [i \in Checks |-> 0],
          scopeEpoch = 0, scopes = 0, opening = 0, active = 0,
          scopePhase = [i \in Scopes |-> "unused"],
          openingEpoch = [i \in Scopes |-> 0],
          owner = [i \in Scopes |-> "launch"],
          callerDone = [i \in Scopes |-> TRUE],
          retired = {}, commandedGPS = {}, physicalGPS = {}, pendingStop = {},
          gpsPhase = [i \in Scopes |-> "idle"],
          retirement = "idle",
          tasks = 0, taskOwner = 0, taskPhase = [i \in Tasks |-> "unused"],
          badOpen = FALSE, badInstall = FALSE, badGPS = FALSE,
          staleCheckRejected = FALSE, staleOpenRejected = FALSE, staleScopeEpochRejected = FALSE,
          blockedOpening = FALSE, pendingRetiredGPS = FALSE,
          didRelease = FALSE, recovered = FALSE, failedOpen = FALSE,
          repeatedLockout = FALSE;

define {
    Allowed == decision = "allowed"
    LiveContainers == {i \in Scopes : scopePhase[i] \in {"opening", "active", "discarding"}}
    CallersDrained == \A i \in Scopes : callerDone[i]
}

macro RequestRetirement() {
    repeatedLockout := repeatedLockout \/
        (didRelease /\ active # 0 /\ taskOwner # 0 /\ taskPhase[taskOwner] = "relaunch");
    if (Implementation # "retainedTask" \/ taskOwner = 0) {
        taskPhase := [task \in Tasks |-> IF task = tasks + 1 THEN "queued"
            ELSE IF task = taskOwner THEN
                IF taskPhase[task] = "queued" THEN "canceledQueued" ELSE "superseded"
            ELSE taskPhase[task]] ||
        tasks := tasks + 1 || taskOwner := tasks + 1 || retirement := "requested";
    };
}

process (BeginCheck = "BeginCheck") {
BeginCheckStep:
    while (TRUE) {
        await currentCheck = 0 /\ checks < MaxChecks;
        checks := checks + 1 || currentCheck := checks + 1 ||
        checkPhase[checks + 1] := "waiting" || checkEpoch[checks + 1] := accountEpoch;
    }
}

process (CompleteCheck \in {<<"CompleteCheck", i>> : i \in Checks}) {
CompleteCheckStep:
    while (TRUE) {
        with (i = self[2]) {
            await checkPhase[i] = "waiting";
            if (checkEpoch[i] = accountEpoch \/ Implementation = "uncheckedVerification") {
                with (compatible \in BOOLEAN) {
                    if (Allowed /\ ~compatible) { RequestRetirement(); };
                    blockedOpening := blockedOpening \/ (~compatible /\ opening # 0) ||
                    decision := IF compatible THEN "allowed" ELSE "blocked" ||
                    decisionEpoch := checkEpoch[i];
                };
            } else {
                staleCheckRejected := TRUE;
            };
            checkPhase[i] := "done" ||
            currentCheck := IF currentCheck = i THEN 0 ELSE currentCheck;
        };
    }
}

process (AccountChange = "AccountChange") {
AccountChangeStep:
    while (TRUE) {
        await accountEpoch < MaxAccountChanges;
        if (Allowed) { RequestRetirement(); };
        accountEpoch := accountEpoch + 1 || currentCheck := 0 ||
        blockedOpening := blockedOpening \/ opening # 0 || decision := "blocked";
    }
}

process (BeginOpen = "BeginOpen") {
BeginOpenStep:
    while (TRUE) {
        await (Allowed \/ Implementation = "ungatedOpen") /\ retirement = "idle" /\
              opening = 0 /\ active = 0 /\ scopes < MaxScopes;
        with (caller \in {"launch", "onboarding"}) {
            scopes := scopes + 1 || opening := scopes + 1 ||
            scopePhase[scopes + 1] := "opening" || openingEpoch[scopes + 1] := scopeEpoch ||
            owner[scopes + 1] := caller || callerDone[scopes + 1] := FALSE ||
            badOpen := badOpen \/ ~Allowed \/ decisionEpoch # accountEpoch ||
            recovered := recovered \/ didRelease;
        };
    }
}

process (CompleteOpen \in {<<"CompleteOpen", i>> : i \in Scopes}) {
CompleteOpenStep:
    while (TRUE) {
        with (i = self[2]) {
            await scopePhase[i] = "opening";
            either {
                scopePhase[i] := "discarding" || failedOpen := TRUE;
            } or {
                if ((Allowed /\ (openingEpoch[i] = scopeEpoch \/ Implementation = "uncheckedScopeEpoch")) \/
                    Implementation = "uncheckedOpening") {
                    scopePhase[i] := "active" || active := i || opening := 0 ||
                    badInstall := badInstall \/ ~Allowed \/ openingEpoch[i] # scopeEpoch;
                } else {
                    scopePhase[i] := "discarding" || staleOpenRejected := TRUE ||
                    staleScopeEpochRejected := staleScopeEpochRejected \/ openingEpoch[i] # scopeEpoch;
                };
            };
        };
    }
}

process (BeginGPS \in {<<"BeginGPS", i>> : i \in Scopes}) {
BeginGPSStep:
    while (TRUE) {
        with (i = self[2]) {
            await scopePhase[i] = "active" /\ ~callerDone[i] /\ gpsPhase[i] = "idle";
            gpsPhase[i] := IF i \notin retired \/ Implementation = "revivableGPS"
                           THEN "authorizing" ELSE "done";
        };
    }
}

process (AuthorizeGPS \in {<<"AuthorizeGPS", i>> : i \in Scopes}) {
AuthorizeGPSStep:
    while (TRUE) {
        with (i = self[2]) {
            await gpsPhase[i] = "authorizing";
            if (i \notin retired \/ Implementation = "revivableGPS") {
                gpsPhase[i] := "starting" || commandedGPS := commandedGPS \cup {i} ||
                badGPS := badGPS \/ i \in retired;
            } else { gpsPhase[i] := "done"; };
        };
    }
}

process (PhysicalStart \in {<<"PhysicalStart", i>> : i \in Scopes}) {
PhysicalStartStep:
    while (TRUE) {
        with (i = self[2]) {
            await gpsPhase[i] = "starting";
            physicalGPS := physicalGPS \cup {i} || gpsPhase[i] := "returning";
        };
    }
}

process (StartReturns \in {<<"StartReturns", i>> : i \in Scopes}) {
StartReturnsStep:
    while (TRUE) {
        with (i = self[2]) {
            await gpsPhase[i] = "returning";
            gpsPhase[i] := IF i \in retired /\ Implementation # "lateGPS" THEN "cleanup" ELSE "done";
        };
    }
}

process (StopLateStart \in {<<"StopLateStart", i>> : i \in Scopes}) {
StopLateStartStep:
    while (TRUE) {
        with (i = self[2]) {
            await gpsPhase[i] = "cleanup";
            physicalGPS := physicalGPS \ {i} || gpsPhase[i] := "done";
        };
    }
}

process (FinishCaller \in {<<"FinishCaller", i>> : i \in Scopes}) {
FinishCallerStep:
    while (TRUE) {
        with (i = self[2]) {
            await scopePhase[i] \in {"active", "discarding"} /\ ~callerDone[i] /\
                  gpsPhase[i] \in {"idle", "done"};
            callerDone[i] := TRUE;
        };
    }
}

process (DiscardOpen \in {<<"DiscardOpen", i>> : i \in Scopes}) {
DiscardOpenStep:
    while (TRUE) {
        with (i = self[2]) {
            await scopePhase[i] = "discarding" /\ callerDone[i];
            scopePhase[i] := "released" || opening := 0 || retired := retired \cup {i};
        };
    }
}

process (StopBeforeDrain = "StopBeforeDrain") {
StopBeforeDrainStep:
    while (TRUE) {
        await retirement = "requested";
        taskPhase[taskOwner] := "teardown" ||
        retired := IF active = 0 THEN retired ELSE retired \cup {active} ||
        pendingStop := pendingStop \cup (commandedGPS \cap {active}) ||
        commandedGPS := commandedGPS \ {active} ||
        pendingRetiredGPS := pendingRetiredGPS \/
            (active # 0 /\ gpsPhase[active] \in {"authorizing", "starting", "returning"}) ||
        retirement := "stopping";
    }
}

process (StopHardware = "StopHardware") {
StopHardwareStep:
    while (TRUE) {
        await retirement = "stopping";
        physicalGPS := physicalGPS \ pendingStop || pendingStop := {} || retirement := "launchDrain";
    }
}

process (InvalidateScope = "InvalidateScope") {
InvalidateScopeStep:
    while (TRUE) {
        await retirement = "launchDrain" /\
              (\A i \in Scopes : owner[i] = "launch" => callerDone[i]);
        scopeEpoch := scopeEpoch + 1 ||
        retired := IF active = 0 THEN retired ELSE retired \cup {active} ||
        pendingStop := pendingStop \cup (commandedGPS \cap {active}) ||
        commandedGPS := commandedGPS \ {active} ||
        pendingRetiredGPS := pendingRetiredGPS \/
            (active # 0 /\ gpsPhase[active] \in {"authorizing", "starting", "returning"}) ||
        retirement := IF Implementation = "earlyRelaunch" THEN "idle" ELSE "onboardingStop" ||
        active := IF Implementation = "earlyRelaunch" THEN 0 ELSE active;
    }
}

process (StopAfterInvalidation = "StopAfterInvalidation") {
StopAfterInvalidationStep:
    while (TRUE) {
        await retirement = "onboardingStop";
        physicalGPS := physicalGPS \ pendingStop || pendingStop := {} || retirement := "onboardingDrain";
    }
}

process (ReleaseScope = "ReleaseScope") {
ReleaseScopeStep:
    while (TRUE) {
        await retirement = "onboardingDrain" /\ CallersDrained /\ opening = 0;
        scopePhase := [i \in Scopes |-> IF scopePhase[i] = "active" THEN "released" ELSE scopePhase[i]] ||
        active := 0 || retirement := "idle" || didRelease := didRelease \/ active # 0 ||
        taskPhase[taskOwner] := "relaunch";
    }
}

process (FinishRetirementTask \in {<<"FinishRetirementTask", i>> : i \in Tasks}) {
FinishRetirementTaskStep:
    while (TRUE) {
        with (i = self[2]) {
            await taskPhase[i] \in {"superseded", "canceledQueued"} \/
                  (taskPhase[i] = "relaunch" /\ active # 0 /\ callerDone[active]);
            taskPhase[i] := "done" || taskOwner := IF taskOwner = i THEN 0 ELSE taskOwner;
        };
    }
}

process (LateCanceledTask \in {<<"LateCanceledTask", i>> : i \in Tasks}) {
LateCanceledTaskStep:
    while (TRUE) {
        with (i = self[2]) {
            await Implementation = "lateRetirement" /\ taskPhase[i] = "canceledQueued" /\
                  Allowed /\ retirement = "idle" /\ active # 0;
            retired := retired \cup {active} || taskPhase[i] := "done";
        };
    }
}

process (Parked = "Parked") {
ParkedStep:
    while (TRUE) {
        await retirement = "idle" /\ CallersDrained /\ opening = 0 /\
              (\A i \in Checks : checkPhase[i] # "waiting");
        skip;
    }
}
} *)

TypeOK ==
    /\ accountEpoch \in 0..MaxAccountChanges /\ decisionEpoch \in 0..MaxAccountChanges
    /\ decision \in {"checking", "allowed", "blocked"}
    /\ checks \in 0..MaxChecks /\ currentCheck \in 0..MaxChecks
    /\ checkPhase \in [Checks -> {"unused", "waiting", "done"}]
    /\ checkEpoch \in [Checks -> 0..MaxAccountChanges]
    /\ scopeEpoch \in 0..(MaxChecks + MaxAccountChanges)
    /\ scopes \in 0..MaxScopes /\ opening \in 0..MaxScopes /\ active \in 0..MaxScopes
    /\ scopePhase \in [Scopes -> ScopePhases]
    /\ openingEpoch \in [Scopes -> 0..(MaxChecks + MaxAccountChanges)]
    /\ owner \in [Scopes -> {"launch", "onboarding"}] /\ callerDone \in [Scopes -> BOOLEAN]
    /\ retired \subseteq Scopes /\ physicalGPS \subseteq Scopes /\ gpsPhase \in [Scopes -> GPSPhases]
    /\ commandedGPS \subseteq Scopes /\ pendingStop \subseteq Scopes
    /\ retirement \in {"idle", "requested", "stopping", "launchDrain", "onboardingStop", "onboardingDrain"}
    /\ tasks \in 0..(MaxChecks + MaxAccountChanges) /\ taskOwner \in 0..(MaxChecks + MaxAccountChanges)
    /\ taskPhase \in [Tasks -> {"unused", "queued", "teardown", "relaunch", "canceledQueued", "superseded", "done"}]
    /\ {badOpen, badInstall, badGPS, staleCheckRejected, staleOpenRejected, staleScopeEpochRejected,
         blockedOpening, pendingRetiredGPS, didRelease, recovered, failedOpen, repeatedLockout} \subseteq BOOLEAN

CurrentDecisionOnly == Allowed => decisionEpoch = accountEpoch
AdmissionRequiresCurrentDecision == ~badOpen
NoStaleScopeInstallation == ~badInstall
ReleaseBeforeReplacement == Cardinality(LiveContainers) <= 1
RetiredScopeCannotReauthorizeGPS == ~badGPS
ReleasedScopeHasNoGPS == \A i \in Scopes : scopePhase[i] = "released" => i \notin physicalGPS
BlockedScopeHasRetirement == decision = "blocked" /\ active # 0 => retirement # "idle"
NoObsoleteTaskRetiresReplacement == Allowed /\ retirement = "idle" /\ active # 0 => active \notin retired

StaleVerificationNotReached == ~staleCheckRejected
OpeningLockoutNotReached == ~(blockedOpening /\ staleOpenRejected)
StaleScopeEpochNotReached == ~staleScopeEpochRejected
RetiredPendingGPSNotReached == ~pendingRetiredGPS
RecoveryNotReached == ~recovered
FailedOpenNotReached == ~failedOpen
RepeatedLockoutNotReached == ~repeatedLockout
====
