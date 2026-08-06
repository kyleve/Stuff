---- MODULE ScopeExclusivity ----
EXTENDS Integers

CONSTANTS Implementation

ASSUME Implementation \in {"current", "broken"}

ActiveScopes == {"none", "real", "demo"}

VARIABLES
    activeScope,
    realContainersAlive,
    demoContainerOpen,
    onboardingGate,
    flyoverBuilt

vars == <<activeScope, realContainersAlive, demoContainerOpen, onboardingGate,
          flyoverBuilt>>

Init ==
    /\ activeScope = "none"
    /\ realContainersAlive = 0
    /\ demoContainerOpen = FALSE
    /\ onboardingGate = TRUE
    /\ flyoverBuilt = FALSE

ClearOnboardingGate ==
    /\ onboardingGate
    /\ onboardingGate' = FALSE
    /\ UNCHANGED <<activeScope, realContainersAlive, demoContainerOpen, flyoverBuilt>>

ResolveRealScope ==
    /\ ~onboardingGate
    /\ IF Implementation = "current"
          THEN /\ activeScope = "none"
               /\ realContainersAlive = 0
          ELSE activeScope \in {"none", "real"}
    /\ activeScope' = "real"
    /\ realContainersAlive' = realContainersAlive + 1
    /\ UNCHANGED <<demoContainerOpen, onboardingGate, flyoverBuilt>>

LogOut ==
    /\ activeScope \in {"real", "demo"}
    /\ activeScope' = "none"
    /\ IF activeScope = "real"
          THEN realContainersAlive' = 0
          ELSE UNCHANGED realContainersAlive
    /\ IF activeScope = "demo"
          THEN demoContainerOpen' = FALSE
          ELSE UNCHANGED demoContainerOpen
    /\ onboardingGate' = TRUE
    /\ UNCHANGED flyoverBuilt

ActivateDemo ==
    /\ ~onboardingGate
    /\ activeScope \in {"none", "real"}
    /\ activeScope' = "demo"
    /\ demoContainerOpen' = TRUE
    /\ IF activeScope = "real"
          THEN realContainersAlive' = 0
          ELSE UNCHANGED realContainersAlive
    /\ UNCHANGED <<onboardingGate, flyoverBuilt>>

BuildFlyoverSibling ==
    /\ demoContainerOpen' = TRUE
    /\ flyoverBuilt' = TRUE
    /\ UNCHANGED <<activeScope, realContainersAlive, onboardingGate>>

Stutter ==
    UNCHANGED vars

Next ==
    \/ ClearOnboardingGate
    \/ ResolveRealScope
    \/ LogOut
    \/ ActivateDemo
    \/ BuildFlyoverSibling
    \/ Stutter

Fairness ==
    /\ WF_vars(ClearOnboardingGate)
    /\ WF_vars(ResolveRealScope)
    /\ WF_vars(LogOut)
    /\ WF_vars(ActivateDemo)
    /\ WF_vars(BuildFlyoverSibling)

Spec == Init /\ [][Next]_vars /\ Fairness

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
