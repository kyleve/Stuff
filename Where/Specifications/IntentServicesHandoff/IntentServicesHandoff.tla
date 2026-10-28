---- MODULE IntentServicesHandoff ----
EXTENDS Integers, FiniteSets
CONSTANT Implementation
ASSUME Implementation \in {"current", "self-create", "clear-unblocks", "double-resume"}
Consumers == {"first", "second"}
Epochs == {1, 2}

(* --algorithm IntentServicesHandoffAlgorithm {
variables availability = "awaiting", installed = 0, nextEpoch = 1, revoked = {},
          phase = [c \in Consumers |-> "idle"],
          context = [c \in Consumers |-> 0],
          theme = [c \in Consumers |-> 0],
          parked = {}, resumed = [c \in Consumers |-> 0],
          selfCreated = FALSE, didBlock = FALSE, recovered = FALSE,
          oldReadAfterRecovery = FALSE, clearLostBlock = FALSE;

process (Request \in Consumers) {
RequestStep:
    while (TRUE) {
        await phase[self] = "idle";
        if (availability = "blocked") { phase[self] := "rejected"; }
        else if (availability = "installed") {
            phase[self] := "holding" || context[self] := installed || theme[self] := installed;
        } else if (Implementation = "self-create") {
            selfCreated := TRUE || phase[self] := "holding" || context[self] := 1 || theme[self] := 1;
        } else { parked := parked \cup {self} || phase[self] := "parked"; };
    }
}
process (Install = "install") {
InstallStep:
    while (TRUE) {
        await availability = "awaiting" /\ nextEpoch \in Epochs /\
              (nextEpoch = 1 \/ recovered);
        installed := nextEpoch || availability := "installed" || nextEpoch := nextEpoch + 1 ||
        phase := [c \in Consumers |-> IF c \in parked THEN "holding" ELSE phase[c]] ||
        context := [c \in Consumers |-> IF c \in parked THEN nextEpoch ELSE context[c]] ||
        theme := [c \in Consumers |-> IF c \in parked THEN nextEpoch ELSE theme[c]] ||
        resumed := [c \in Consumers |-> IF c \in parked THEN resumed[c] + 1 ELSE resumed[c]];
        if (Implementation # "double-resume") { parked := {}; };
    }
}
process (Cancel \in {<<"cancel", c>> : c \in Consumers}) {
CancelStep:
    while (TRUE) {
        with (c = self[2]) {
            await c \in parked;
            parked := parked \ {c} || phase[c] := "cancelled" || resumed[c] := resumed[c] + 1;
        };
    }
}
process (Block = "block") {
BlockStep:
    while (TRUE) {
        await ~didBlock /\ installed # 0;
        availability := "blocked" || revoked := revoked \cup {installed} || installed := 0 ||
        didBlock := TRUE ||
        phase := [c \in Consumers |-> IF c \in parked THEN "rejected" ELSE phase[c]] ||
        resumed := [c \in Consumers |-> IF c \in parked THEN resumed[c] + 1 ELSE resumed[c]] ||
        parked := {};
        \* Already-resumed consumers retain their old context across block and recovery.
    }
}
process (Clear = "clear") {
ClearStep:
    while (TRUE) {
        if (availability = "installed") { availability := "awaiting" || installed := 0; }
        else if (availability = "blocked" /\ Implementation = "clear-unblocks") {
            availability := "awaiting" || clearLostBlock := TRUE;
        };
    }
}
process (Recover = "recover") {
RecoverStep:
    while (TRUE) {
        await availability = "blocked";
        availability := "awaiting" || recovered := TRUE;
    }
}
fair process (Use \in {<<"use", c>> : c \in Consumers}) {
UseStep:
    while (TRUE) {
        with (c = self[2]) {
            await phase[c] = "holding";
            phase[c] := "returned" ||
            oldReadAfterRecovery := oldReadAfterRecovery \/ (recovered /\ context[c] \in revoked);
        };
    }
}
process (Stutter = "stutter") { StutterStep: while (TRUE) { skip; } }
} *)

TypeOK == /\ installed \in 0..2 /\ nextEpoch \in 1..3 /\ revoked \subseteq Epochs
          /\ availability \in {"awaiting", "installed", "blocked"}
          /\ parked \subseteq Consumers /\ context \in [Consumers -> 0..2]
          /\ phase \in [Consumers -> {"idle", "parked", "holding", "returned", "rejected", "cancelled"}]
NoSelfCreate == ~selfCreated
WaiterAtMostOnce == \A c \in Consumers : resumed[c] <= 1
NoMixedContext == context = theme
BlockHasNoWaiters == availability = "blocked" => (parked = {} /\ installed = 0)
ClearPreservesBlock == ~clearLostBlock
ResumedConsumerFinishes == \A c \in Consumers : (phase[c] = "holding") ~> (phase[c] \in {"returned", "rejected"})
OldReadAfterRecoveryNotReached == ~oldReadAfterRecovery
TwoWaitersNotReached == Cardinality(parked) < 2
====
