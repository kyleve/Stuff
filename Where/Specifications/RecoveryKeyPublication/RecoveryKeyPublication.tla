---- MODULE RecoveryKeyPublication ----
EXTENDS Integers, FiniteSets

CONSTANTS Implementation, DeviceCount
ASSUME /\ Implementation \in {"current", "mutable-slot", "publish-first"}
       /\ DeviceCount \in 2..3
Devices == 1..DeviceCount
Keys == Devices
Phases == {"idle", "preserve", "pin", "export", "done"}

(* --algorithm RecoveryKeyPublicationAlgorithm {
variables unlocked = FALSE,
          phase = [d \in Devices |-> "idle"],
          ring = [d \in Devices |-> {}],
          pin = [d \in Devices |-> 0],
          chosen = [d \in Devices |-> 0],
          crashed = {},
          failed = {},
          archives = {},
          publishedWithoutKey = FALSE;

fair process (Unlock = "unlock") {
UnlockStep:
    while (TRUE) { await ~unlocked; unlocked := TRUE; }
}
fair process (ReadOrGenerate = "read") {
ReadOrGenerateStep:
    while (TRUE) {
        with (d \in Devices) {
            await unlocked /\ phase[d] = "idle";
            chosen[d] := IF pin[d] # 0 THEN pin[d] ELSE d ||
            phase[d] := IF Implementation = "publish-first" THEN "export" ELSE "preserve";
        };
    }
}
fair process (Preserve = "preserve") {
PreserveStep:
    while (TRUE) {
        with (d \in Devices) {
            await phase[d] = "preserve";
            ring[d] := IF Implementation = "mutable-slot" THEN {chosen[d]}
                       ELSE ring[d] \cup {chosen[d]} ||
            phase[d] := "pin";
        };
    }
}
fair process (Pin = "pin") {
PinStep:
    while (TRUE) {
        with (d \in Devices) {
            await phase[d] = "pin";
            pin[d] := IF pin[d] = 0 THEN chosen[d] ELSE pin[d] || phase[d] := "export";
        };
    }
}
fair process (Export = "export") {
ExportStep:
    while (TRUE) {
        with (d \in Devices) {
            await phase[d] = "export";
            archives := archives \cup {chosen[d]} || phase[d] := "done" ||
            publishedWithoutKey := publishedWithoutKey \/ chosen[d] \notin ring[d];
        };
    }
}
process (Crash = "crash") {
CrashStep:
    while (TRUE) {
        with (d \in Devices \ crashed) {
            await phase[d] \in {"preserve", "pin", "export"};
            crashed := crashed \cup {d} || chosen[d] := 0 || phase[d] := "idle";
        };
    }
}
process (FailKeychain = "failure") {
FailKeychainStep:
    while (TRUE) {
        with (d \in Devices \ failed) {
            await phase[d] = "preserve";
            failed := failed \cup {d} || chosen[d] := 0 || phase[d] := "idle";
        };
    }
}
fair process (Synchronize = "sync") {
SynchronizeStep:
    while (TRUE) {
        with (a \in Devices, b \in Devices) {
            await a # b /\ ring[a] \ ring[b] # {};
            ring[b] := IF Implementation = "mutable-slot" THEN ring[a] ELSE ring[b] \cup ring[a];
        };
    }
}
process (Idle = "idle") {
IdleStep:
    while (TRUE) { skip; }
}
} *)

TypeOK ==
    /\ unlocked \in BOOLEAN /\ phase \in [Devices -> Phases]
    /\ ring \in [Devices -> SUBSET Keys]
    /\ pin \in [Devices -> (Keys \cup {0})] /\ chosen \in [Devices -> (Keys \cup {0})]
    /\ crashed \subseteq Devices /\ failed \subseteq Devices /\ archives \subseteq Keys
    /\ publishedWithoutKey \in BOOLEAN
KeyPrecedesArchive == ~publishedWithoutKey
RecoveryKeysSurviveSync == archives \subseteq UNION {ring[d] : d \in Devices}
PinnedKeyIsPreserved == \A d \in Devices : pin[d] = 0 \/ pin[d] \in ring[d]
NoCreationBeforeUnlock == ~unlocked => (UNION {ring[d] : d \in Devices} = {} /\ archives = {})
EventuallyExported == <> (archives = Keys)
EventuallySynchronized == <> (\A d \in Devices : ring[d] = Keys)
CriticalStateNotReached == ~(archives = Keys /\ crashed # {} /\ failed # {} /\ \A d \in Devices : ring[d] = Keys)
====
