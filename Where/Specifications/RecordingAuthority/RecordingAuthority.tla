---- MODULE RecordingAuthority ----
EXTENDS Integers, FiniteSets, Sequences
CONSTANTS Implementation, AllowRecovery, MaxRevision, MaxCommands, InitialRequest, ExerciseFailures
ASSUME Implementation \in {"current", "lost-response", "removed-target", "missing-fence", "secondary-upgrade", "cancel-fence"}
Devices == {"phone", "replacement"}
None == "none"
Other(d) == IF d = "phone" THEN "replacement" ELSE "phone"
EmptyCommand == [kind |-> None, expected |-> 0, target |-> None, token |-> <<None, 0>>]
Command(d, n, k, r, t) == [kind |-> k, expected |-> r, target |-> t, token |-> <<d, n>>]

(* --algorithm RecordingAuthorityAlgorithm {
variables owner = "phone", ownershipID = 1, revision = IF InitialRequest THEN 2 ELSE 1, floor = 1,
          request = IF InitialRequest THEN "replacement" ELSE None,
          cachedOwner = [d \in Devices |-> "phone"],
          cachedRevision = [d \in Devices |-> IF InitialRequest THEN 2 ELSE 1],
          cachedOwnershipID = [d \in Devices |-> 1],
          command = [d \in Devices |-> EmptyCommand],
          commands = [d \in Devices |-> 0],
          phase = [d \in Devices |-> "idle"],
          running = {"phone"}, runningOwnershipID = [d \in Devices |-> 1],
          commits = {}, rejected = {}, inFlight = {}, crashed = {}, removed = {}, recovered = FALSE,
          lastUpgradeActor = None, lastUpgradeOwner = None,
          transferCount = 0, lostReply = FALSE, reconciledLostReply = FALSE;

process (User \in Devices) {
UserStep:
    while (TRUE) {
        either {
            await phase[self] = "idle" /\ command[self] = EmptyCommand /\
                  commands[self] < MaxCommands /\ cachedOwner[self] # self /\ request = None /\
                  revision < MaxRevision;
            command[self] := Command(self, commands[self] + 1, "request", cachedRevision[self], self) ||
            commands[self] := commands[self] + 1 || phase[self] := "send";
        } or {
            await phase[self] = "idle" /\ command[self] = EmptyCommand /\
                  commands[self] < MaxCommands /\ owner = self /\ request # None /\
                  revision < MaxRevision /\
                  (Implementation = "removed-target" \/ request \notin removed);
            command[self] := Command(self, commands[self] + 1, "transfer", revision, request) ||
            commands[self] := commands[self] + 1 || phase[self] := "stop";
        } or {
            await command[self].kind # "transfer" /\
                  (Implementation = "cancel-fence" \/ command[self].kind # "cancel") /\
                  cachedOwner[self] = self /\ self \notin removed;
            running := running \cup {self} || runningOwnershipID[self] := cachedOwnershipID[self];
        } or {
            await ExerciseFailures /\ self \notin crashed;
            crashed := crashed \cup {self} || running := running \ {self} || phase[self] := "idle";
            if (Implementation = "missing-fence") { command[self] := EmptyCommand; };
        } or {
            await phase[self] = "idle" /\ command[self] # EmptyCommand /\
                  command[self].token \notin commits;
            phase[self] := IF command[self].kind = "transfer" THEN "stop" ELSE "send";
        } or {
            await ExerciseFailures /\ Other(self) # owner /\ Other(self) \notin removed /\
                  (Implementation = "removed-target" \/ request # Other(self));
            removed := removed \cup {Other(self)};
        } or {
            await ExerciseFailures /\ phase[self] = "idle" /\ commands[self] < MaxCommands /\ request # None /\
                  command[self].kind # "cancel" /\
                  (self = owner \/ self = request) /\ revision < MaxRevision;
            command[self] := Command(self, commands[self] + 1, "cancel", revision, None) ||
            commands[self] := commands[self] + 1 || phase[self] := "send";
        } or {
            await ExerciseFailures /\ phase[self] = "await";
            phase[self] := "idle" || lostReply := TRUE;
        } or {
            await ExerciseFailures /\ floor = 1 /\ cachedRevision[self] = revision /\ revision < MaxRevision /\
                  (Implementation = "secondary-upgrade" \/ self = owner);
            floor := 2 || revision := revision + 1 || request := None ||
            lastUpgradeActor := self || lastUpgradeOwner := owner;
        } or {
            await AllowRecovery /\ ~recovered /\ self # owner /\ self \notin removed /\
                  cachedRevision[self] = revision /\ revision < MaxRevision;
            owner := self || ownershipID := revision + 1 || revision := revision + 1 ||
            request := None || recovered := TRUE;
        };
    }
}

fair process (Stop \in {<<"stop", d>> : d \in Devices}) {
StopStep:
    while (TRUE) {
        with (d = self[2]) {
            await phase[d] = "stop";
            running := running \ {d} || phase[d] := "send";
        };
    }
}

fair process (Send \in {<<"send", d>> : d \in Devices}) {
SendStep:
    while (TRUE) {
        with (d = self[2]) {
            await phase[d] = "send";
            inFlight := inFlight \cup {command[d]} || phase[d] := "await";
        };
    }
}

process (Server = "server") {
ServerStep:
    while (TRUE) {
        with (proposal \in inFlight) {
            inFlight := inFlight \ {proposal};
            if (proposal.token \notin commits) {
                if (proposal.expected = revision /\ revision < MaxRevision) {
                    if (proposal.kind = "request") { request := proposal.target; }
                    else if (proposal.kind = "cancel") { request := None; }
                    else {
                        owner := proposal.target || ownershipID := revision + 1 || request := None ||
                        transferCount := transferCount + 1;
                    };
                    revision := revision + 1 || commits := commits \cup {proposal.token};
                } else { rejected := rejected \cup {proposal.token}; };
            };
        };
    }
}

process (Reply \in {<<"reply", d>> : d \in Devices}) {
ReplyStep:
    while (TRUE) {
        with (d = self[2]) {
            await phase[d] = "await" /\
                  command[d].token \in commits \cup rejected;
            either {
                await ExerciseFailures;
                phase[d] := "idle" || lostReply := TRUE;
            } or {
                phase[d] := "idle" || command[d] := EmptyCommand ||
                cachedOwner[d] := owner || cachedRevision[d] := revision || cachedOwnershipID[d] := ownershipID;
            };
        };
    }
}

fair process (Refresh \in {<<"refresh", d>> : d \in Devices}) {
RefreshStep:
    while (TRUE) {
        with (d = self[2]) {
            cachedOwner[d] := owner || cachedRevision[d] := revision || cachedOwnershipID[d] := ownershipID;
            if (d # owner \/ d \in removed) { running := running \ {d}; };
            if (phase[d] = "idle" /\ command[d].token \in commits \cup rejected /\
                Implementation # "lost-response") {
                command[d] := EmptyCommand || reconciledLostReply := lostReply;
            };
        };
    }
}

process (Stutter = "stutter") { StutterStep: while (TRUE) { skip; } }
} *)

TypeOK == /\ owner \in Devices /\ request \in Devices \cup {None}
          /\ revision \in 1..MaxRevision /\ floor \in {1, 2}
          /\ running \subseteq Devices /\ removed \subseteq Devices /\ crashed \subseteq Devices
          /\ phase \in [Devices -> {"idle", "stop", "send", "await"}]
NormalHandoffExclusive == recovered \/ Cardinality(running) <= 1
OwnerIsEligible == owner \notin removed
OwnerOnlyUpgrade == lastUpgradeActor = lastUpgradeOwner
CommittedPendingSettles == \A d \in Devices, n \in 1..MaxCommands :
    (phase[d] = "idle" /\ command[d].token = <<d, n>> /\ <<d, n>> \in commits)
        ~> (command[d].token # <<d, n>>)
LostReplyWasNotReconciled == ~reconciledLostReply
PhoneNeverReacquired == ~(transferCount = 2 /\ "phone" \in running /\ runningOwnershipID["phone"] > 1)
RecoveryNeverOverlapped == ~(recovered /\ Cardinality(running) > 1)
====
