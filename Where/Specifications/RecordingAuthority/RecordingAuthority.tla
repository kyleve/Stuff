---- MODULE RecordingAuthority ----
EXTENDS Integers, FiniteSets
CONSTANT Implementation
ASSUME Implementation \in {"current", "broken"}
Devices == {"phone", "replacement"}

(* --algorithm RecordingAuthorityAlgorithm {
variables owner = "none", revision = 0, floor = 1,
          observed = [d \in Devices |-> 0],
          pending = "none", stopped = {},
          lastUpgradeOwner = "none", lastUpgradeActor = "none",
          starts = {};
process (Device \in Devices) {
Step:
    while (TRUE) {
        either {
            observed[self] := revision;
        } or {
            await owner = "none" /\ revision < 3;
            owner := self || revision := revision + 1;
        } or {
            await owner # "none" /\ owner # self /\ pending = "none";
            pending := self;
        } or {
            await owner = self /\ pending # "none";
            stopped := stopped \cup {self} || starts := starts \ {self};
        } or {
            await owner = self /\ pending # "none" /\ self \in stopped /\ revision < 3;
            owner := pending || pending := "none" || revision := revision + 1;
        } or {
            await owner = self /\ self \notin stopped;
            starts := starts \cup {self};
        } or {
            await floor = 1 /\ observed[self] = revision /\ revision < 3 /\
                  (Implementation = "broken" \/ owner = self);
            floor := 2 || revision := revision + 1 || pending := "none" ||
            lastUpgradeOwner := owner || lastUpgradeActor := self;
        } or {
            skip;
        };
    }
}
} *)

AtMostOneRecorder == Cardinality(starts) <= 1
OwnerOnlyUpgrade == lastUpgradeActor = lastUpgradeOwner
TypeOK == /\ owner \in Devices \cup {"none"}
          /\ floor \in {1, 2}
          /\ revision \in 0..3
          /\ starts \subseteq Devices
====
