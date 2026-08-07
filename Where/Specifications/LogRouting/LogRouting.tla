---- MODULE LogRouting ----
EXTENDS Integers

CONSTANTS Implementation, Scopes

ASSUME /\ Implementation \in {"current", "broken"}
       /\ Scopes = {"real", "demo"}

RoutingStates == {"pending", "routing", "idleNoStore", "idleWithStore"}
ActiveScopes == Scopes \union {"none"}

VARIABLES
    activeScope,
    realRouting,
    demoRouting,
    globalSinkOwner,
    realStoreOpen,
    demoStoreOpen

vars == <<activeScope, realRouting, demoRouting, globalSinkOwner,
          realStoreOpen, demoStoreOpen>>

Init ==
    /\ activeScope = "none"
    /\ realRouting = "pending"
    /\ demoRouting = "pending"
    /\ globalSinkOwner = "none"
    /\ realStoreOpen = FALSE
    /\ demoStoreOpen = FALSE

ActivateReal ==
    /\ activeScope' = "real"
    /\ IF realStoreOpen
          THEN /\ realRouting' = "routing"
               /\ globalSinkOwner' = "real"
          ELSE /\ realRouting' = "pending"
               /\ globalSinkOwner' = IF demoRouting = "routing" THEN "demo" ELSE "none"
    /\ IF demoRouting = "routing"
          THEN demoRouting' = IF demoStoreOpen THEN "idleWithStore" ELSE "idleNoStore"
          ELSE UNCHANGED demoRouting
    /\ UNCHANGED <<realStoreOpen, demoStoreOpen>>

ActivateDemo ==
    /\ activeScope' = "demo"
    /\ IF demoStoreOpen
          THEN /\ demoRouting' = "routing"
               /\ globalSinkOwner' = "demo"
          ELSE /\ demoRouting' = "pending"
               /\ globalSinkOwner' = IF realRouting = "routing" THEN "real" ELSE "none"
    /\ IF realRouting = "routing"
          THEN realRouting' = IF realStoreOpen THEN "idleWithStore" ELSE "idleNoStore"
          ELSE UNCHANGED realRouting
    /\ UNCHANGED <<realStoreOpen, demoStoreOpen>>

DeactivateDemo ==
    /\ activeScope = "demo"
    /\ activeScope' = "none"
    /\ IF demoRouting = "routing"
          THEN demoRouting' = IF demoStoreOpen THEN "idleWithStore" ELSE "idleNoStore"
          ELSE UNCHANGED demoRouting
    /\ globalSinkOwner' = "none"
    /\ UNCHANGED <<realRouting, realStoreOpen, demoStoreOpen>>

RealStoreOpensLate ==
    /\ ~realStoreOpen
    /\ realStoreOpen' = TRUE
    /\ IF activeScope = "real"
          THEN /\ realRouting' = "routing"
               /\ globalSinkOwner' = "real"
          ELSE IF Implementation = "broken"
                  THEN /\ realRouting' = "routing"
                       /\ globalSinkOwner' = "real"
                  ELSE /\ realRouting' = "idleWithStore"
                       /\ globalSinkOwner' = IF activeScope = "demo" /\ demoRouting = "routing"
                                                THEN "demo"
                                                ELSE "none"
    /\ UNCHANGED <<activeScope, demoRouting, demoStoreOpen>>

DemoStoreOpensLate ==
    /\ ~demoStoreOpen
    /\ demoStoreOpen' = TRUE
    /\ IF activeScope = "demo"
          THEN /\ demoRouting' = "routing"
               /\ globalSinkOwner' = "demo"
          ELSE IF Implementation = "broken"
                  THEN /\ demoRouting' = "routing"
                       /\ globalSinkOwner' = "demo"
                  ELSE /\ demoRouting' = "idleWithStore"
               /\ globalSinkOwner' = IF activeScope = "real" /\ realRouting = "routing"
                                        THEN "real"
                                        ELSE "none"
    /\ UNCHANGED <<activeScope, realRouting, realStoreOpen>>

EmitRecord ==
    /\ globalSinkOwner /= "none"
    /\ UNCHANGED vars

Next ==
    \/ ActivateReal
    \/ ActivateDemo
    \/ DeactivateDemo
    \/ RealStoreOpensLate
    \/ DemoStoreOpensLate
    \/ EmitRecord

Fairness ==
    /\ WF_vars(ActivateReal)
    /\ WF_vars(ActivateDemo)
    /\ WF_vars(DeactivateDemo)
    /\ WF_vars(RealStoreOpensLate)
    /\ WF_vars(DemoStoreOpensLate)
    /\ WF_vars(EmitRecord)

Spec == Init /\ [][Next]_vars /\ Fairness

TypeOK ==
    /\ activeScope \in ActiveScopes
    /\ realRouting \in RoutingStates
    /\ demoRouting \in RoutingStates
    /\ globalSinkOwner \in ActiveScopes
    /\ realStoreOpen \in BOOLEAN
    /\ demoStoreOpen \in BOOLEAN

GlobalSinkSingleOwner ==
    (realRouting = "routing") \/ (demoRouting = "routing")
        => globalSinkOwner \in {"real", "demo"}

ShadowedScopeNeverRoutes ==
    /\ activeScope /= "real" => realRouting /= "routing"
    /\ activeScope /= "demo" => demoRouting /= "routing"

ActiveScopeRecordsReachSink ==
    /\ (activeScope = "real" => (realRouting /= "routing" \/ globalSinkOwner = "real"))
    /\ (activeScope = "demo" => (demoRouting /= "routing" \/ globalSinkOwner = "demo"))

====
