---- MODULE ScopeExclusivity ----
EXTENDS Integers

CONSTANTS Implementation

ASSUME Implementation \in {"current", "broken"}

ActiveScopes == {"none", "real", "demo"}

(* --algorithm ScopeExclusivityAlgorithm {
variables activeScope = "none",
          realContainersAlive = 0,
          demoContainerOpen = FALSE,
          onboardingGate = TRUE,
          flyoverBuilt = FALSE;

fair process (ClearOnboardingGate = "ClearOnboardingGate") {
ClearOnboardingGateStep:
    while (TRUE) {
        await onboardingGate;
        onboardingGate := FALSE;
    }
}

fair process (ResolveRealScope = "ResolveRealScope") {
ResolveRealScopeStep:
    while (TRUE) {
        await ~onboardingGate /\
              (IF Implementation = "current"
                   THEN activeScope = "none" /\ realContainersAlive = 0
                   ELSE activeScope \in {"none", "real"});
        activeScope := "real" ||
        realContainersAlive := realContainersAlive + 1;
    }
}

fair process (LogOut = "LogOut") {
LogOutStep:
    while (TRUE) {
        await activeScope \in {"real", "demo"};
        activeScope := "none" ||
        realContainersAlive := IF activeScope = "real" THEN 0 ELSE realContainersAlive ||
        demoContainerOpen := IF activeScope = "demo" THEN FALSE ELSE demoContainerOpen ||
        onboardingGate := TRUE;
    }
}

fair process (ActivateDemo = "ActivateDemo") {
ActivateDemoStep:
    while (TRUE) {
        await ~onboardingGate /\ activeScope \in {"none", "real"};
        activeScope := "demo" ||
        demoContainerOpen := TRUE ||
        realContainersAlive := IF activeScope = "real" THEN 0 ELSE realContainersAlive;
    }
}

fair process (BuildFlyoverSibling = "BuildFlyoverSibling") {
BuildFlyoverSiblingStep:
    while (TRUE) {
        demoContainerOpen := TRUE ||
        flyoverBuilt := TRUE;
    }
}

process (Stutter = "Stutter") {
StutterStep:
    while (TRUE) {
        skip;
    }
}
} *)

TypeOK ==
    /\ activeScope \in ActiveScopes
    /\ realContainersAlive \in 0..2
    /\ demoContainerOpen \in BOOLEAN
    /\ onboardingGate \in BOOLEAN
    /\ flyoverBuilt \in BOOLEAN

AtMostOneActiveScope ==
    activeScope \in ActiveScopes

GateBeforeOpen ==
    onboardingGate => realContainersAlive = 0

NoOverlappingRealContainers ==
    realContainersAlive <= 1

RealReleasedBeforeRelogin ==
    activeScope = "none" => realContainersAlive = 0

====
