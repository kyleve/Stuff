---- MODULE CompatibilityOutputs ----
EXTENDS Integers, FiniteSets
CONSTANT Implementation
ASSUME Implementation \in {"current", "early-replacement", "late-withdrawal", "missing-recheck"}
Epochs == {1, 2}

(* --algorithm CompatibilityOutputsAlgorithm {
variables active = 1, verified = TRUE, revoked = {},
          lifetime = [e \in Epochs |-> "active"],
          operation = [e \in Epochs |-> "idle"], started = {},
          output = 0, didBlock = FALSE, recovered = FALSE,
          invalidReturn = FALSE, replacementErased = FALSE,
          lateCompletion = FALSE;
process (BeginPublish \in Epochs) {
BeginStep:
    while (TRUE) {
        await active = self /\ verified /\ self \notin revoked /\ self \notin started /\
              lifetime[self] = "active";
        started := started \cup {self} || operation[self] := "external";
    }
}
fair process (External \in {<<"external", e>> : e \in Epochs}) {
ExternalStep:
    while (TRUE) {
        with (e = self[2]) {
            await operation[e] = "external";
            output := e || operation[e] := "validate";
            if (e \in revoked) { lateCompletion := TRUE; };
        };
    }
}
fair process (Finish \in {<<"finish", e>> : e \in Epochs}) {
FinishStep:
    while (TRUE) {
        with (e = self[2]) {
            await operation[e] = "validate";
            if (e \in revoked \/ lifetime[e] # "active") {
                if (Implementation = "missing-recheck") { invalidReturn := TRUE; }
                else {
                    replacementErased := output = 2 /\ e = 1 || output := 0 || lifetime[e] := "retired";
                };
            };
            operation[e] := "done";
        };
    }
}
process (Block = "block") {
BlockStep:
    while (TRUE) {
        await ~didBlock;
        verified := FALSE || revoked := {1} || lifetime[1] := "retiring" || didBlock := TRUE;
    }
}
fair process (Drain = "drain") {
DrainStep:
    while (TRUE) {
        await lifetime[1] = "retiring" /\ operation[1] \in {"idle", "done"};
        replacementErased := output = 2 || output := 0 || lifetime[1] := "retired";
    }
}
process (Recover = "recover") {
RecoverStep:
    while (TRUE) {
        await didBlock /\ ~recovered /\
              (Implementation = "early-replacement" \/ lifetime[1] = "retired");
        active := 2 || verified := TRUE || recovered := TRUE;
    }
}
process (StaleRetire = "stale-retire") {
StaleRetireStep:
    while (TRUE) {
        await lifetime[1] = "retired";
        if (Implementation = "late-withdrawal") {
            replacementErased := output = 2 || output := 0;
        };
    }
}
process (Stutter = "stutter") { StutterStep: while (TRUE) { skip; } }
} *)

TypeOK == /\ active \in Epochs /\ revoked \subseteq Epochs /\ output \in 0..2
          /\ lifetime \in [Epochs -> {"active", "retiring", "retired"}]
          /\ operation \in [Epochs -> {"idle", "external", "validate", "done"}]
NoInvalidReturn == ~invalidReturn
ReplacementOutputSurvives == ~replacementErased
RetiredOutputIsGone == lifetime[1] = "retired" => output # 1
BlockEventuallyDrains == didBlock ~> (lifetime[1] = "retired")
SuspendedPublicationNotReached == ~lateCompletion
RecoveryPublicationNotReached == ~(recovered /\ output = 2 /\ lifetime[1] = "retired")
====
