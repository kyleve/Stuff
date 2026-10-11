---- MODULE ScopeExclusivity ----
EXTENDS Integers, FiniteSets
CONSTANT Implementation
ASSUME Implementation \in {"current", "duplicate-container", "revived-permit", "ungated-scope"}
Epochs == {1, 2}

(* --algorithm ScopeExclusivityAlgorithm {
variables realContainersAlive = 0, activeScopes = {}, nextEpoch = 1,
          onboardingGate = TRUE, verified = FALSE, permits = {}, revoked = {},
          suspended = {}, completed = {}, invalidCompletion = FALSE,
          didBlock = FALSE, retiredWithBootstrap = FALSE, flyoverBuilt = FALSE;

process (Bootstrap = "bootstrap") {
BootstrapStep:
    while (TRUE) {
        await realContainersAlive = 0;
        realContainersAlive := 1;
    }
}
process (Verify = "verify") {
VerifyStep:
    while (TRUE) {
        await realContainersAlive = 1;
        verified := TRUE;
    }
}
process (Confirm = "confirm") {
ConfirmStep: while (TRUE) { onboardingGate := FALSE; }
}
process (Resolve = "resolve") {
ResolveStep:
    while (TRUE) {
        await realContainersAlive > 0 /\ activeScopes = {} /\ nextEpoch \in Epochs /\
              (Implementation = "ungated-scope" \/ (verified /\ ~onboardingGate));
        activeScopes := {nextEpoch} ||
        permits := IF Implementation = "revived-permit" THEN 1..nextEpoch ELSE {nextEpoch} ||
        nextEpoch := nextEpoch + 1;
        if (Implementation = "duplicate-container") { realContainersAlive := realContainersAlive + 1; };
    }
}
process (Suspend = "suspend") {
SuspendStep:
    while (TRUE) {
        with (e \in activeScopes) { suspended := suspended \cup {e}; };
    }
}
process (Resume = "resume") {
ResumeStep:
    while (TRUE) {
        with (e \in suspended \ completed) {
            completed := completed \cup {e};
            if (e \in permits /\ e \in revoked) { invalidCompletion := TRUE; };
        };
    }
}
process (Block = "block") {
BlockStep:
    while (TRUE) {
        await activeScopes # {} /\ ~didBlock;
        revoked := revoked \cup activeScopes || permits := {} ||
        verified := FALSE || activeScopes := {} || didBlock := TRUE ||
        retiredWithBootstrap := realContainersAlive = 1;
    }
}
process (Flyover = "flyover") {
FlyoverStep: while (TRUE) { flyoverBuilt := TRUE; }
}
process (Stutter = "stutter") { StutterStep: while (TRUE) { skip; } }
} *)

TypeOK == /\ realContainersAlive \in 0..2 /\ activeScopes \subseteq Epochs
          /\ permits \subseteq Epochs /\ revoked \subseteq Epochs /\ nextEpoch \in 1..3
          /\ suspended \subseteq Epochs /\ completed \subseteq Epochs
AtMostOneActiveScope == Cardinality(activeScopes) <= 1
NoOverlappingRealContainers == realContainersAlive <= 1
GateBeforeScope == activeScopes # {} => (verified /\ ~onboardingGate)
NoRevivedPermit == permits \cap revoked = {}
SuspendedWorkCannotRecover == ~invalidCompletion
RetainedBootstrapNotReached == ~retiredWithBootstrap
ReplacementNotReached == ~(1 \in revoked /\ activeScopes = {2})
====
