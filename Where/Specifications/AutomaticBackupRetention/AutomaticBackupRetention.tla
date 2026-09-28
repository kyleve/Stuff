---- MODULE AutomaticBackupRetention ----
EXTENDS Integers, FiniteSets

CONSTANTS Implementation, DeviceCount
ASSUME /\ Implementation \in {"review", "candidate", "unauthenticated", "retry-on-maintenance", "stale-candidate"}
       /\ DeviceCount \in 1..2
Devices == 1..DeviceCount
ValidFiles == 1..(3 + DeviceCount)
Files == 1..(5 + DeviceCount)
Locations == 0..DeviceCount
UnknownKey == 4 + DeviceCount
Forged == 5 + DeviceCount
Retain == 3
WritePhases == {"cloud", "local", "stored", "done"}
ScanPhases == {"idle", "validate", "delete", "done"}

(* --algorithm AutomaticBackupRetentionAlgorithm {
variables copies = [f \in Files |-> IF f \in (1..3) \cup {UnknownKey, Forged} THEN {0} ELSE {}],
          revision = [f \in Files |-> 0],
          cloudAvailable = [d \in Devices |-> TRUE],
          cloudTransitions = [d \in Devices |-> 0],
          writePhase = [d \in Devices |-> "cloud"],
          scanPhase = [d \in Devices |-> "idle"],
          pending = [d \in Devices |-> {}],
          verified = [d \in Devices |-> {}],
          hashes = [d \in Devices |-> [f \in Files |-> 0]],
          considered = [d \in Devices |-> {}],
          mutated = FALSE,
          maintenanceFailed = {},
          removedUnknown = FALSE,
          removedChanged = FALSE,
          unsafeDeletion = FALSE,
          removed = {};

define {
    Accessible(d) == {f \in Files : d \in copies[f] \/ (cloudAvailable[d] /\ 0 \in copies[f])}
    Healthy(d) == {f \in Accessible(d) \cap ValidFiles : revision[f] = 0}
    Keepers(d) == {f \in verified[d] : Cardinality({g \in verified[d] : g > f}) < Retain}
    Candidates(d) == verified[d] \ Keepers(d)
}

fair process (CloudWrite = "cloud-write") {
CloudWriteStep:
    while (TRUE) {
        with (d \in Devices) {
            await writePhase[d] = "cloud";
            either {
                await cloudAvailable[d];
                copies[3 + d] := copies[3 + d] \cup {0} || writePhase[d] := "stored";
            } or {
                writePhase[d] := "local";
            };
        };
    }
}
fair process (LocalWrite = "local-write") {
LocalWriteStep:
    while (TRUE) {
        with (d \in Devices) {
            await writePhase[d] = "local";
            either {
                copies[3 + d] := copies[3 + d] \cup {d} || writePhase[d] := "stored";
            } or {
                writePhase[d] := "done" || scanPhase[d] := "done";
            };
        };
    }
}
process (MaintenanceFailure = "maintenance-failure") {
MaintenanceFailureStep:
    while (TRUE) {
        with (d \in Devices \ maintenanceFailed) {
            await writePhase[d] = "stored" /\ scanPhase[d] = "idle";
            maintenanceFailed := maintenanceFailed \cup {d};
            if (Implementation = "retry-on-maintenance") { writePhase[d] := "local"; };
        };
    }
}
fair process (Enumerate = "enumerate") {
EnumerateStep:
    while (TRUE) {
        with (d \in Devices) {
            await writePhase[d] = "stored" /\ scanPhase[d] = "idle";
            pending[d] := Accessible(d) || scanPhase[d] := "validate" || writePhase[d] := "done";
        };
    }
}
fair process (Validate = "validate") {
ValidateStep:
    while (TRUE) {
        with (d \in Devices) {
            await scanPhase[d] = "validate";
            if (pending[d] = {}) { scanPhase[d] := "delete"; }
            else {
                with (f = CHOOSE g \in pending[d] : \A h \in pending[d] : g >= h) {
                    pending[d] := pending[d] \ {f};
                    if (f \in Healthy(d) \/ (Implementation = "unauthenticated" /\ f \in Accessible(d))) {
                        verified[d] := verified[d] \cup {f} || hashes[d][f] := revision[f];
                    };
                };
            };
        };
    }
}
process (ChangeFile = "change-file") {
ChangeFileStep:
    while (TRUE) {
        await ~mutated;
        with (f \in ValidFiles) {
            await copies[f] # {};
            revision[f] := 1 || mutated := TRUE;
        };
    }
}
process (ChangeAvailability = "availability") {
ChangeAvailabilityStep:
    while (TRUE) {
        with (d \in Devices) {
            await cloudTransitions[d] < 2;
            cloudAvailable[d] := ~cloudAvailable[d] || cloudTransitions[d] := cloudTransitions[d] + 1;
        };
    }
}
fair process (Prune = "prune") {
PruneStep:
    while (TRUE) {
        with (d \in Devices) {
            await scanPhase[d] = "delete";
            if (Candidates(d) \ considered[d] = {}) { scanPhase[d] := "done"; }
            else {
                with (f \in Candidates(d) \ considered[d]) {
                    considered[d] := considered[d] \cup {f};
                    if (f \in Accessible(d)
                        /\ (revision[f] = hashes[d][f] \/ Implementation = "stale-candidate")
                        /\ (Implementation # "candidate"
                            \/ (Keepers(d) \subseteq Accessible(d)
                                /\ \A k \in Keepers(d) : revision[k] = hashes[d][k]))) {
                        copies[f] := {} || removed := removed \cup {f} ||
                        removedUnknown := removedUnknown \/ f \notin ValidFiles ||
                        removedChanged := removedChanged \/ revision[f] # hashes[d][f] ||
                        unsafeDeletion := unsafeDeletion \/ Cardinality(Healthy(d) \ {f}) < Retain;
                    };
                };
            };
        };
    }
}
process (Idle = "idle") {
IdleStep:
    while (TRUE) { skip; }
}
} *)

TypeOK ==
    /\ copies \in [Files -> SUBSET Locations] /\ revision \in [Files -> 0..1]
    /\ cloudAvailable \in [Devices -> BOOLEAN] /\ cloudTransitions \in [Devices -> 0..2]
    /\ writePhase \in [Devices -> WritePhases] /\ scanPhase \in [Devices -> ScanPhases]
    /\ pending \in [Devices -> SUBSET Files] /\ verified \in [Devices -> SUBSET Files]
    /\ hashes \in [Devices -> [Files -> 0..1]] /\ considered \in [Devices -> SUBSET Files]
    /\ mutated \in BOOLEAN /\ maintenanceFailed \subseteq Devices
    /\ removedUnknown \in BOOLEAN /\ removedChanged \in BOOLEAN /\ unsafeDeletion \in BOOLEAN
    /\ removed \subseteq Files
PreserveUnknownFiles == ~removedUnknown
PreserveChangedCandidates == ~removedChanged
DeletionLeavesThreeHealthyFiles == ~unsafeDeletion
NoDuplicateFallback == \A f \in Files : Cardinality(copies[f]) <= 1
EventuallySettled == <> (\A d \in Devices : scanPhase[d] = "done")
CriticalStateNotReached == ~(mutated /\ removed # {} /\ maintenanceFailed # {})
====
