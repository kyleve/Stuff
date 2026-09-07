---- MODULE LogRouting ----
EXTENDS Integers

CONSTANTS Implementation, Scopes

ASSUME /\ Implementation \in {"current", "broken"}
       /\ Scopes = {"real", "demo"}

RoutingStates == {"pending", "routing", "idleNoStore", "idleWithStore"}
ActiveScopes == Scopes \union {"none"}

(* --algorithm LogRoutingAlgorithm {
variables activeScope = "none",
          realRouting = "pending",
          demoRouting = "pending",
          globalSinkOwner = "none",
          realStoreOpen = FALSE,
          demoStoreOpen = FALSE;

fair process (ActivateReal = "ActivateReal") {
ActivateRealStep:
    while (TRUE) {
        activeScope := "real" ||
        realRouting := IF realStoreOpen THEN "routing" ELSE "pending" ||
        globalSinkOwner := IF realStoreOpen
                               THEN "real"
                               ELSE IF demoRouting = "routing" THEN "demo" ELSE "none" ||
        demoRouting := IF demoRouting = "routing"
                           THEN IF demoStoreOpen THEN "idleWithStore" ELSE "idleNoStore"
                           ELSE demoRouting;
    }
}

fair process (ActivateDemo = "ActivateDemo") {
ActivateDemoStep:
    while (TRUE) {
        activeScope := "demo" ||
        demoRouting := IF demoStoreOpen THEN "routing" ELSE "pending" ||
        globalSinkOwner := IF demoStoreOpen
                               THEN "demo"
                               ELSE IF realRouting = "routing" THEN "real" ELSE "none" ||
        realRouting := IF realRouting = "routing"
                           THEN IF realStoreOpen THEN "idleWithStore" ELSE "idleNoStore"
                           ELSE realRouting;
    }
}

fair process (DeactivateDemo = "DeactivateDemo") {
DeactivateDemoStep:
    while (TRUE) {
        await activeScope = "demo";
        activeScope := "none" ||
        demoRouting := IF demoRouting = "routing"
                           THEN IF demoStoreOpen THEN "idleWithStore" ELSE "idleNoStore"
                           ELSE demoRouting ||
        globalSinkOwner := "none";
    }
}

fair process (RealStoreOpensLate = "RealStoreOpensLate") {
RealStoreOpensLateStep:
    while (TRUE) {
        await ~realStoreOpen;
        realStoreOpen := TRUE ||
        realRouting := IF activeScope = "real" \/ Implementation = "broken"
                           THEN "routing"
                           ELSE "idleWithStore" ||
        globalSinkOwner := IF activeScope = "real" \/ Implementation = "broken"
                               THEN "real"
                               ELSE IF activeScope = "demo" /\ demoRouting = "routing"
                                        THEN "demo"
                                        ELSE "none";
    }
}

fair process (DemoStoreOpensLate = "DemoStoreOpensLate") {
DemoStoreOpensLateStep:
    while (TRUE) {
        await ~demoStoreOpen;
        demoStoreOpen := TRUE ||
        demoRouting := IF activeScope = "demo" \/ Implementation = "broken"
                           THEN "routing"
                           ELSE "idleWithStore" ||
        globalSinkOwner := IF activeScope = "demo" \/ Implementation = "broken"
                               THEN "demo"
                               ELSE IF activeScope = "real" /\ realRouting = "routing"
                                        THEN "real"
                                        ELSE "none";
    }
}

fair process (EmitRecord = "EmitRecord") {
EmitRecordStep:
    while (TRUE) {
        await globalSinkOwner /= "none";
        skip;
    }
}
} *)

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
