---- MODULE CompatibilityPublication ----
EXTENDS Integers, Sequences, FiniteSets

CONSTANTS Implementation, Builds, Writers, InitialServer, InitialReceipts, InitialAccount, MaxRefreshes

Devices == 1..Len(Builds)
Accounts == {1, 2}
Versions == 0..3
Max(a, b) == IF a > b THEN a ELSE b
Version(record) == Max(1, record)
Receipt(a, v, ok) == [account |-> a, version |-> v, verified |-> ok]
EmptyReceipt == Receipt(0, 0, FALSE)
NoReceipts == [d \in Devices |-> 0]
CurrentReceipts == [d \in Devices |-> Builds[d]]
DifferentBuilds == <<2, 3>>
SameBuilds == <<2, 2>>
BaselineBuild == <<1>>
UpgradedBuild == <<2>>
BothWriters == <<TRUE, TRUE>>
ViewerAndWriter == <<FALSE, TRUE>>
Viewer == <<FALSE>>
Phases == {"idle", "account", "read", "readReply", "eligibility", "prepareSave",
           "commit", "saveReply", "persist", "error", "done"}

ASSUME /\ Implementation \in {"current", "viewerPublishes", "unconditionalSave",
                              "wrongAccountOffline", "cacheAdmits", "failedReceiptAdmits"}
       /\ Builds \in Seq(1..3) /\ Len(Builds) > 0
       /\ Writers \in Seq(BOOLEAN) /\ Len(Writers) = Len(Builds)
       /\ InitialServer \in Versions /\ InitialReceipts \in [Devices -> Versions]
       /\ InitialAccount \in Accounts /\ MaxRefreshes > 0

(* --algorithm CompatibilityPublicationAlgorithm {
variables server = [a \in Accounts |-> InitialServer],
          account = [d \in Devices |-> InitialAccount], epoch = [d \in Devices |-> 0],
          receipt = [d \in Devices |-> IF InitialReceipts[d] = 0 THEN EmptyReceipt
                      ELSE Receipt(1, InitialReceipts[d], TRUE)],
          known = [d \in Devices |-> 1], state = [d \in Devices |-> "checking"],
          refreshes = [d \in Devices |-> 0], phase = [d \in Devices |-> "idle"],
          attempt = [d \in Devices |-> 0], capturedEpoch = [d \in Devices |-> 0],
          resolvedAccount = [d \in Devices |-> 0], prior = [d \in Devices |-> EmptyReceipt],
          observed = [d \in Devices |-> 0], eligible = [d \in Devices |-> FALSE],
          evidence = [d \in Devices |-> 0], error = [d \in Devices |-> "none"],
          grantAccount = [d \in Devices |-> 0], offlineReceipt = [d \in Devices |-> EmptyReceipt],
          badPublisher = FALSE, badServerDecrease = FALSE,
          sawConflict = FALSE, sawLostReply = FALSE, sawOffline = FALSE,
          sawAccountDuringRequest = FALSE, sawViewerBaseline = FALSE,
          sawReceiptFailure = FALSE, sawRecovery = FALSE, sawForeignReceipt = FALSE;

process (Begin \in {<<"Begin", d>> : d \in Devices}) {
BeginStep:
    while (TRUE) {
        with (d = self[2]) {
            await phase[d] \in {"idle", "done"} /\ refreshes[d] < MaxRefreshes;
            refreshes[d] := refreshes[d] + 1 || capturedEpoch[d] := epoch[d] ||
            prior[d] := receipt[d] || resolvedAccount[d] := 0 || attempt[d] := 1 ||
            known[d] := Max(known[d], receipt[d].version) ||
            phase[d] := IF Max(known[d], receipt[d].version) > Builds[d] THEN "done" ELSE "account" ||
            state[d] := IF Max(known[d], receipt[d].version) > Builds[d] THEN "blocked" ELSE state[d];
        };
    }
}

process (ChangeAccount \in {<<"ChangeAccount", d>> : d \in Devices}) {
ChangeAccountStep:
    while (TRUE) {
        with (d = self[2]) {
            await epoch[d] = 0;
            account[d] := 2 || epoch[d] := 1 || state[d] := "blocked" ||
            known[d] := Max(known[d], receipt[d].version) ||
            receipt[d] := IF receipt[d].account = 0 THEN receipt[d]
                          ELSE Receipt(receipt[d].account, Max(known[d], receipt[d].version), FALSE) ||
            sawAccountDuringRequest := sawAccountDuringRequest \/ phase[d] \notin {"idle", "done"};
        };
    }
}

process (ResolveAccount \in {<<"ResolveAccount", d>> : d \in Devices}) {
ResolveAccountStep:
    while (TRUE) {
        with (d = self[2]) {
            await phase[d] = "account";
            if (capturedEpoch[d] # epoch[d]) { phase[d] := "done"; }
            else {
                either {
                    sawForeignReceipt := sawForeignReceipt \/
                        (prior[d].verified /\ prior[d].account # account[d]);
                    resolvedAccount[d] := account[d] || phase[d] := "read" ||
                    prior[d] := IF prior[d].account = account[d] \/ Implementation = "wrongAccountOffline"
                                THEN prior[d] ELSE EmptyReceipt;
                } or {
                    error[d] := "unavailable" || phase[d] := "error";
                };
            };
        };
    }
}

process (Read \in {<<"Read", d>> : d \in Devices}) {
ReadStep:
    while (TRUE) {
        with (d = self[2]) {
            await phase[d] = "read";
            if (capturedEpoch[d] # epoch[d]) { phase[d] := "done"; }
            else {
                either {
                    observed[d] := server[resolvedAccount[d]] || phase[d] := "readReply";
                } or {
                    with (failure \in {"unavailable", "hard"}) {
                        error[d] := failure || phase[d] := "error";
                    };
                };
            };
        };
    }
}

process (ReadReply \in {<<"ReadReply", d>> : d \in Devices}) {
ReadReplyStep:
    while (TRUE) {
        with (d = self[2]) {
            await phase[d] = "readReply";
            if (capturedEpoch[d] # epoch[d]) { phase[d] := "done"; }
            else {
                known[d] := Max(known[d], Version(observed[d])) || evidence[d] := Version(observed[d]);
                if (known[d] > Builds[d]) {
                    with (saveOK \in BOOLEAN) {
                        receipt[d] := IF saveOK THEN Receipt(resolvedAccount[d], known[d], FALSE) ELSE receipt[d] ||
                        state[d] := "blocked" || phase[d] := "done";
                    };
                } else { phase[d] := "eligibility"; };
            };
        };
    }
}

process (Eligibility \in {<<"Eligibility", d>> : d \in Devices}) {
EligibilityStep:
    while (TRUE) {
        with (d = self[2]) {
            await phase[d] = "eligibility";
            if (capturedEpoch[d] # epoch[d]) { phase[d] := "done"; }
            else {
                eligible[d] := Writers[d];
                if (Version(observed[d]) < Builds[d] /\ ~eligible[d] /\ Implementation # "viewerPublishes") {
                    if (Implementation = "cacheAdmits" /\ known[d] = Builds[d]) {
                        phase[d] := "persist";
                    } else {
                        with (saveOK \in BOOLEAN) {
                            receipt[d] := IF saveOK THEN Receipt(resolvedAccount[d], known[d], FALSE) ELSE receipt[d] ||
                            state[d] := "blocked" || phase[d] := "done";
                        };
                    };
                } else if (Version(observed[d]) < Builds[d] \/ (observed[d] = 0 /\ eligible[d])) {
                    phase[d] := "prepareSave";
                } else { phase[d] := "persist"; };
            };
        };
    }
}

process (PrepareSave \in {<<"PrepareSave", d>> : d \in Devices}) {
PrepareSaveStep:
    while (TRUE) {
        with (d = self[2]) {
            await phase[d] = "prepareSave";
            if (capturedEpoch[d] # epoch[d]) { phase[d] := "done"; }
            else if (observed[d] # 0 /\ Implementation # "unconditionalSave" /\
                     (server[resolvedAccount[d]] # observed[d] \/ server[resolvedAccount[d]] > Builds[d])) {
                sawConflict := TRUE || attempt[d] := attempt[d] + 1 ||
                phase[d] := IF attempt[d] < 3 THEN "read" ELSE "error" || error[d] := "hard";
            } else { phase[d] := "commit"; };
        };
    }
}

process (Commit \in {<<"Commit", d>> : d \in Devices}) {
CommitStep:
    while (TRUE) {
        with (d = self[2]) {
            await phase[d] = "commit";
            either {
                error[d] := "unavailable" || phase[d] := "error";
            } or {
                if (server[resolvedAccount[d]] = observed[d] \/ Implementation = "unconditionalSave") {
                    badPublisher := badPublisher \/ ~eligible[d] ||
                    badServerDecrease := badServerDecrease \/ server[resolvedAccount[d]] > Builds[d] ||
                    server[resolvedAccount[d]] := Builds[d];
                    either { phase[d] := "saveReply"; }
                    or {
                        sawLostReply := TRUE || error[d] := "unavailable" || phase[d] := "error";
                    };
                } else {
                    sawConflict := TRUE || attempt[d] := attempt[d] + 1 ||
                    phase[d] := IF attempt[d] < 3 THEN "read" ELSE "error" || error[d] := "hard";
                };
            };
        };
    }
}

process (SaveReply \in {<<"SaveReply", d>> : d \in Devices}) {
SaveReplyStep:
    while (TRUE) {
        with (d = self[2]) {
            await phase[d] = "saveReply";
            if (capturedEpoch[d] # epoch[d]) { phase[d] := "done"; }
            else {
                known[d] := Max(known[d], Builds[d]) || evidence[d] := Builds[d] || phase[d] := "persist";
            };
        };
    }
}

process (Persist \in {<<"Persist", d>> : d \in Devices}) {
PersistStep:
    while (TRUE) {
        with (d = self[2]) {
            await phase[d] = "persist";
            if (capturedEpoch[d] # epoch[d]) { phase[d] := "done"; }
            else {
                with (saveOK \in BOOLEAN) {
                    receipt[d] := IF saveOK THEN Receipt(resolvedAccount[d], known[d], TRUE) ELSE receipt[d] ||
                    state[d] := IF saveOK \/ Implementation = "failedReceiptAdmits" THEN "allowed" ELSE "blocked" ||
                    sawRecovery := sawRecovery \/ (saveOK /\ state[d] = "blocked") ||
                    sawReceiptFailure := sawReceiptFailure \/ ~saveOK ||
                    sawViewerBaseline := sawViewerBaseline \/ (saveOK /\ ~eligible[d] /\ observed[d] = 0 /\ Builds[d] = 1) ||
                    grantAccount[d] := resolvedAccount[d] || phase[d] := "done";
                };
            };
        };
    }
}

process (Fail \in {<<"Fail", d>> : d \in Devices}) {
FailStep:
    while (TRUE) {
        with (d = self[2]) {
            await phase[d] = "error";
            if (capturedEpoch[d] # epoch[d]) { phase[d] := "done"; }
            else {
                if (error[d] = "unavailable" /\ resolvedAccount[d] # 0 /\ prior[d].verified /\
                    (prior[d].account = resolvedAccount[d] \/ Implementation = "wrongAccountOffline") /\
                    prior[d].version = Builds[d] /\ known[d] = Builds[d]) {
                    offlineReceipt[d] := prior[d] || grantAccount[d] := resolvedAccount[d] ||
                    state[d] := "offline" || sawOffline := TRUE;
                } else {
                    with (saveOK \in BOOLEAN) {
                        with (a = IF resolvedAccount[d] # 0 THEN resolvedAccount[d] ELSE prior[d].account) {
                            receipt[d] := IF saveOK /\ a # 0 THEN Receipt(a, known[d], FALSE) ELSE receipt[d] ||
                            state[d] := "blocked";
                        };
                    };
                };
                phase[d] := "done";
            };
        };
    }
}

process (Parked = "Parked") {
ParkedStep:
    while (TRUE) {
        await \A d \in Devices : phase[d] \in {"idle", "done"};
        skip;
    }
}
} *)

ReceiptType == [account : 0..2, version : Versions, verified : BOOLEAN]
TypeOK ==
    /\ server \in [Accounts -> Versions] /\ account \in [Devices -> Accounts]
    /\ epoch \in [Devices -> 0..1] /\ capturedEpoch \in [Devices -> 0..1]
    /\ receipt \in [Devices -> ReceiptType] /\ prior \in [Devices -> ReceiptType]
    /\ offlineReceipt \in [Devices -> ReceiptType] /\ known \in [Devices -> 1..3]
    /\ state \in [Devices -> {"checking", "blocked", "allowed", "offline"}]
    /\ refreshes \in [Devices -> 0..MaxRefreshes] /\ phase \in [Devices -> Phases]
    /\ attempt \in [Devices -> 0..4] /\ resolvedAccount \in [Devices -> 0..2]
    /\ observed \in [Devices -> Versions] /\ evidence \in [Devices -> Versions]
    /\ eligible \in [Devices -> BOOLEAN] /\ error \in [Devices -> {"none", "hard", "unavailable"}]
    /\ grantAccount \in [Devices -> 0..2]
    /\ {badPublisher, badServerDecrease, sawConflict, sawLostReply, sawOffline,
         sawAccountDuringRequest, sawViewerBaseline, sawReceiptFailure, sawRecovery, sawForeignReceipt} \subseteq BOOLEAN

OnlyEligibleRecorderPublishes == ~badPublisher
SharedVersionNeverDecreases == ~badServerDecrease
OnlineAdmissionHasServerEvidence == \A d \in Devices : state[d] = "allowed" => evidence[d] = Builds[d]
ReceiptBeforeOnlineAdmission == \A d \in Devices : state[d] = "allowed" =>
    /\ receipt[d].verified /\ receipt[d].account = account[d] /\ receipt[d].version = Builds[d]
OfflineReceiptIsAccountBound == \A d \in Devices : state[d] = "offline" =>
    /\ offlineReceipt[d].verified /\ offlineReceipt[d].account = account[d]
    /\ grantAccount[d] = account[d] /\ offlineReceipt[d].version = Builds[d] /\ known[d] = Builds[d]
KnownVersionNeverDecreases == [][\A d \in Devices : known'[d] >= known[d]]_vars
ReceiptVersionNeverDecreases == [][\A d \in Devices : receipt'[d].version >= receipt[d].version]_vars

ConflictNotReached == ~sawConflict
LostReplyNotReached == ~sawLostReply
OfflineNotReached == ~sawOffline
AccountChangeDuringRequestNotReached == ~sawAccountDuringRequest
BaselineViewerNotReached == ~sawViewerBaseline
ReceiptFailureNotReached == ~sawReceiptFailure
RecoveryNotReached == ~sawRecovery
ForeignReceiptNotReached == ~sawForeignReceipt
====
