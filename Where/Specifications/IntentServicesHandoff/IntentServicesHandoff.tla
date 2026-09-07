---- MODULE IntentServicesHandoff ----
EXTENDS Integers

CONSTANTS Implementation

ASSUME Implementation \in {"current", "broken"}

Phases == {"idle", "parked", "holding", "cancelled"}
InstallStates == {"none", "installed", "cleared"}

(* --algorithm IntentServicesHandoffAlgorithm {
variables installed = FALSE,
          installState = "none",
          waiterCount = 0,
          consumerPhase = "idle",
          selfCreated = FALSE;

fair process (IntentFiresEarly = "IntentFiresEarly") {
IntentFiresEarlyStep:
    while (TRUE) {
        await consumerPhase = "idle";
        if (installed) {
            consumerPhase := "holding";
        } else if (Implementation = "broken") {
            selfCreated := TRUE ||
            installed := TRUE ||
            consumerPhase := "holding" ||
            installState := "installed";
        } else {
            consumerPhase := "parked" ||
            waiterCount := waiterCount + 1;
        };
    }
}

fair process (Install = "Install") {
InstallStep:
    while (TRUE) {
        await installState \in {"none", "cleared"};
        if (waiterCount > 0) {
            installed := TRUE ||
            installState := "installed" ||
            consumerPhase := "holding" ||
            waiterCount := waiterCount - 1;
        } else {
            installed := TRUE ||
            installState := "installed";
        };
    }
}

fair process (Clear = "Clear") {
ClearStep:
    while (TRUE) {
        await installed;
        installed := FALSE ||
        installState := "cleared" ||
        consumerPhase := IF consumerPhase = "holding" THEN "idle" ELSE consumerPhase;
    }
}

fair process (InstallReplace = "InstallReplace") {
InstallReplaceStep:
    while (TRUE) {
        await installState = "installed";
        if (waiterCount > 0) {
            installed := TRUE ||
            consumerPhase := "holding" ||
            waiterCount := waiterCount - 1;
        } else {
            installed := TRUE;
        };
    }
}

fair process (CancelWaiter = "CancelWaiter") {
CancelWaiterStep:
    while (TRUE) {
        await consumerPhase = "parked" /\ waiterCount > 0;
        consumerPhase := "cancelled" ||
        waiterCount := waiterCount - 1;
    }
}

fair process (ConsumerUsesStack = "ConsumerUsesStack") {
ConsumerUsesStackStep:
    while (TRUE) {
        await consumerPhase = "holding" /\ installed;
        consumerPhase := "idle";
    }
}
} *)

TypeOK ==
    /\ installState \in InstallStates
    /\ waiterCount \in 0..2
    /\ consumerPhase \in Phases
    /\ selfCreated \in BOOLEAN
    /\ installed \in BOOLEAN

NoSelfCreate ==
    ~selfCreated

AtMostOneAuthoritative ==
    ~installed \/ installState = "installed"

WaiterExactlyOnce ==
    consumerPhase /= "parked" \/ waiterCount > 0

AfterClearMustPark ==
    consumerPhase = "holding" => installed

NoMixedWorld ==
    consumerPhase = "holding" => installed

====
