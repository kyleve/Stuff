---- MODULE CompatibilityVerification ----
EXTENDS Integers, FiniteSets
CONSTANTS Dataset, Legacy, Implementation, FailHighWrite
ASSUME Dataset \in {"shared", "local"}
ASSUME Legacy \in BOOLEAN
ASSUME FailHighWrite \in BOOLEAN
ASSUME Implementation \in {"current", "overwrite-init", "stale-grant", "forget-high", "payload-first", "missing-read-fence"}
Clients == {1, 2}
Supported(c) == IF c = 1 THEN 0 ELSE 1
Maximum(a, b) == IF a > b THEN a ELSE b

(* --algorithm CompatibilityVerificationAlgorithm {
variables server = -1, serverHigh = -1,
          localFloor = [c \in Clients |-> -1],
          known = [c \in Clients |-> -1], durable = [c \in Clients |-> -1],
          epoch = [c \in Clients |-> 0],
          requestEpoch = [c \in Clients |-> 0],
          response = [c \in Clients |-> -2],
          access = [c \in Clients |-> -1],
          grantEpoch = [c \in Clients |-> 0],
          records = {}, interpretedUnsupported = FALSE,
          receivedRecordFirst = FALSE, rejectedStale = FALSE,
          verified = [c \in Clients |-> FALSE],
          cacheVerified = [c \in Clients |-> FALSE],
          cachedEpoch = [c \in Clients |-> 0],
          identifiedEpoch = [c \in Clients |-> -1],
          lostMajor = [c \in Clients |-> -1], client = 1;

process (Client = 1) {
Loop:
    while (TRUE) {
        with (chosen \in Clients) { client := chosen; };
        either {
StartVerification:
            await response[client] = -2;
            if (Implementation # "missing-read-fence") { cacheVerified[client] := FALSE; };
            identifiedEpoch[client] := epoch[client];
            response[client] := IF Dataset = "shared" THEN server ELSE localFloor[client];
            requestEpoch[client] := epoch[client];
        } or {
GuardedInitialization:
            await response[client] = -1;
            if (Dataset = "shared") {
                if (server = -1 \/ Implementation = "overwrite-init") {
                    server := IF Legacy THEN 0 ELSE Supported(client);
                    serverHigh := Maximum(serverHigh, IF Legacy THEN 0 ELSE Supported(client));
                };
                response[client] := server;
            } else {
                localFloor[client] := Maximum(localFloor[client], IF Legacy THEN 0 ELSE Supported(client));
                response[client] := localFloor[client];
            };
        } or {
ReceiveVerification:
            await response[client] >= 0;
            known[client] := Maximum(known[client], response[client]);
            if (FailHighWrite /\ response[client] = 1) {
                lostMajor[client] := Maximum(lostMajor[client], 1);
                verified[client] := FALSE || access[client] := -1;
            } else {
                if (requestEpoch[client] = epoch[client] \/ Implementation # "forget-high") {
                    durable[client] := Maximum(durable[client], response[client]);
                };
                if ((requestEpoch[client] = epoch[client] \/ Implementation = "stale-grant")
                    /\ known[client] <= Supported(client)) {
                    verified[client] := TRUE || cacheVerified[client] := TRUE;
                    cachedEpoch[client] := epoch[client];
                    access[client] := known[client];
                    grantEpoch[client] := requestEpoch[client];
                } else {
                    access[client] := -1;
                    rejectedStale := rejectedStale \/ requestEpoch[client] # epoch[client];
                };
            };
            response[client] := -2;
        } or {
InvalidateBinding:
            await epoch[client] < 1;
            epoch[client] := epoch[client] + 1;
            identifiedEpoch[client] := -1;
            verified[client] := FALSE || cacheVerified[client] := FALSE || access[client] := -1;
        } or {
FailedRefresh:
            await response[client] # -2;
            response[client] := -2;
            if (verified[client] /\ identifiedEpoch[client] = epoch[client]
                /\ known[client] <= Supported(client) /\ durable[client] >= known[client]) {
                cacheVerified[client] := TRUE;
            };
            \* Completed transient failure can restore the unchanged live proof to disk.
        } or {
ReceiveRecordHeader:
            await Dataset = "shared" /\ 1 \in records;
            receivedRecordFirst := receivedRecordFirst \/ known[client] < 1;
            known[client] := Maximum(known[client], 1);
            durable[client] := Maximum(durable[client], 1);
            if (Supported(client) < 1) {
                access[client] := -1;
                interpretedUnsupported := interpretedUnsupported \/ Implementation = "payload-first";
            };
        } or {
Relaunch:
            known[client] := durable[client];
            response[client] := -2;
            identifiedEpoch[client] := -1;
            access[client] := -1 || verified[client] := FALSE;
        } or {
EstablishIdentity:
            identifiedEpoch[client] := epoch[client];
        } or {
UseOfflineCache:
            await Dataset = "shared" /\ response[client] = -2
                /\ cacheVerified[client] /\ cachedEpoch[client] = epoch[client]
                /\ identifiedEpoch[client] = epoch[client]
                /\ durable[client] <= Supported(client);
            access[client] := durable[client];
            grantEpoch[client] := epoch[client];
            verified[client] := TRUE;
        };
    };
}

process (Upgrade = 3) {
ConfirmMajor:
    if (Dataset = "shared") {
        await server >= 0;
        server := 1 || serverHigh := 1;
    } else {
        await localFloor[2] >= 0;
        localFloor[2] := 1;
    };
AuthorRecord:
    if (Dataset = "shared") { records := {1}; };
}

process (Stutter = 4) {
Again:
    while (TRUE) { skip; }
}
} *)

TypeOK == /\ server \in -1..1 /\ serverHigh \in -1..1
          /\ localFloor \in [Clients -> -1..1]
          /\ known \in [Clients -> -1..1] /\ durable \in [Clients -> -1..1]
          /\ epoch \in [Clients -> 0..1] /\ requestEpoch \in [Clients -> 0..1]
          /\ response \in [Clients -> -2..1] /\ access \in [Clients -> -1..1]
          /\ grantEpoch \in [Clients -> 0..1] /\ records \subseteq {1}
          /\ interpretedUnsupported \in BOOLEAN /\ receivedRecordFirst \in BOOLEAN
          /\ rejectedStale \in BOOLEAN /\ verified \in [Clients -> BOOLEAN]
          /\ cacheVerified \in [Clients -> BOOLEAN] /\ cachedEpoch \in [Clients -> 0..1]
          /\ identifiedEpoch \in [Clients -> -1..1] /\ lostMajor \in [Clients -> -1..1]
          /\ client \in Clients
          /\ pc \in [{1, 3, 4} ->
              {"Loop", "StartVerification", "GuardedInitialization", "ReceiveVerification",
               "InvalidateBinding", "FailedRefresh", "ReceiveRecordHeader", "Relaunch", "EstablishIdentity", "UseOfflineCache",
               "ConfirmMajor", "AuthorRecord", "Again", "Done"}]
MajorNeverDecreases == server >= serverHigh
NoStaleGrant == \A c \in Clients: access[c] >= 0 => grantEpoch[c] = epoch[c]
KnownIncompatibilityBlocks == \A c \in Clients: known[c] > Supported(c) => access[c] = -1
KnowledgeIsDurable == \A c \in Clients: (~FailHighWrite \/ cacheVerified[c]) => durable[c] >= known[c]
NoObsoleteGrant == \A c \in Clients: access[c] >= 0 => access[c] >= lostMajor[c]
AdmitBeforePayload == ~interpretedUnsupported
NoRecordBeforeConfirmation == records # {} => server >= 1
RecordFirstNotReached == ~receivedRecordFirst
StaleCompletionNotReached == ~rejectedStale
====
