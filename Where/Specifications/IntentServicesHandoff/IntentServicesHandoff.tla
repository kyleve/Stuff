---- MODULE IntentServicesHandoff ----
EXTENDS Integers

CONSTANTS Implementation

ASSUME Implementation \in {"current", "broken"}

Phases == {"idle", "parked", "holding", "cancelled"}
InstallStates == {"none", "installed", "cleared"}

VARIABLES
    installed,
    installState,
    waiterCount,
    consumerPhase,
    selfCreated

vars == <<installed, installState, waiterCount, consumerPhase, selfCreated>>

Init ==
    /\ installed = FALSE
    /\ installState = "none"
    /\ waiterCount = 0
    /\ consumerPhase = "idle"
    /\ selfCreated = FALSE

IntentFiresEarly ==
    /\ consumerPhase = "idle"
    /\ IF installed
          THEN /\ consumerPhase' = "holding"
               /\ UNCHANGED <<installed, installState, waiterCount, selfCreated>>
          ELSE IF Implementation = "broken"
                  THEN /\ selfCreated' = TRUE
                       /\ installed' = TRUE
                       /\ consumerPhase' = "holding"
                       /\ installState' = "installed"
                       /\ UNCHANGED waiterCount
                  ELSE /\ consumerPhase' = "parked"
                       /\ waiterCount' = waiterCount + 1
                       /\ UNCHANGED <<installed, installState, selfCreated>>

Install ==
    /\ installState \in {"none", "cleared"}
    /\ installed' = TRUE
    /\ installState' = "installed"
    /\ IF waiterCount > 0
          THEN /\ consumerPhase' = "holding"
               /\ waiterCount' = waiterCount - 1
          ELSE /\ UNCHANGED <<consumerPhase, waiterCount>>
    /\ UNCHANGED selfCreated

Clear ==
    /\ installed
    /\ installed' = FALSE
    /\ installState' = "cleared"
    /\ IF consumerPhase = "holding"
          THEN consumerPhase' = "idle"
          ELSE UNCHANGED consumerPhase
    /\ UNCHANGED <<waiterCount, selfCreated>>

InstallReplace ==
    /\ installState = "installed"
    /\ installed' = TRUE
    /\ IF waiterCount > 0
          THEN /\ consumerPhase' = "holding"
               /\ waiterCount' = waiterCount - 1
          ELSE /\ UNCHANGED <<consumerPhase, waiterCount>>
    /\ UNCHANGED <<installState, selfCreated>>

CancelWaiter ==
    /\ consumerPhase = "parked"
    /\ waiterCount > 0
    /\ consumerPhase' = "cancelled"
    /\ waiterCount' = waiterCount - 1
    /\ UNCHANGED <<installed, installState, selfCreated>>

ConsumerUsesStack ==
    /\ consumerPhase = "holding"
    /\ installed
    /\ consumerPhase' = "idle"
    /\ UNCHANGED <<installed, installState, waiterCount, selfCreated>>

Next ==
    \/ IntentFiresEarly
    \/ Install
    \/ Clear
    \/ InstallReplace
    \/ CancelWaiter
    \/ ConsumerUsesStack

Fairness ==
    /\ WF_vars(Install)
    /\ WF_vars(Clear)
    /\ WF_vars(InstallReplace)
    /\ WF_vars(CancelWaiter)
    /\ WF_vars(ConsumerUsesStack)
    /\ WF_vars(IntentFiresEarly)

Spec == Init /\ [][Next]_vars /\ Fairness

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
