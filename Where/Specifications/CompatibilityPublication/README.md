# Compatibility version publication

Can a viewer advance the shared version, a competing older writer lower it, or
an offline receipt grant access for a different account or model version?

**Verified for these model bounds and assumptions.** All deliberately broken
variants are **falsified** by the expected properties. No production defect was
found in this publication model. This is bounded protocol evidence, not a
verification of CloudKit's implementation or notification delivery.

```sh
./tla-check CompatibilityPublication
```

## Boundary and source correspondence

Modeled source: `04cb13b2cf83b01e617f3f0bd569d2c7aec2dd6a`; the publication
coordinator/transport implementation is unchanged by these specifications.
The installation permission and demo eligibility adapter was re-reviewed with
the 2026-11-17 startup revision; fixed eligibility remains a model assumption.
[DataCompatibilityCoordinator](../../WhereCore/Sources/Compatibility/DataCompatibilityCoordinator.swift)
owns the local decision; [CloudKitDataCompatibilityTransport](../../WhereCore/Sources/Compatibility/CloudKitDataCompatibilityTransport.swift)
owns conditional metadata saves; [DataCompatibilityReceipt](../../WhereCore/Sources/Compatibility/DataCompatibilityReceipt.swift)
owns the atomic device-local receipt. Scope teardown is in
[CompatibilityLockout](../CompatibilityLockout/README.md).

Publication admission is the coordinator's checked eligibility result before
`advance`. A shared write linearizes at CloudKit's conditional save. Its reply
can be lost after the commit. Online admission follows a successful receipt
save, using an equal-version server read or acknowledged save. Offline admission
requires a prior verified receipt with a successfully resolved matching account,
equal build version, and no higher known floor.

| Model state | Production fact |
| --- | --- |
| `server` | Independent canonical control record per account. `0` means absent; its effective baseline is `1`. |
| `account`, `epoch` | Observed account identity and coordinator invalidation epoch. |
| `receipt`, `known`, `state` | Durable receipt, process-local maximum observed version, and public access decision; these are separate authorities. |
| `refreshes`, `phase`, `attempt`, `capturedEpoch` | Verification trigger budget, async task phase, three-attempt conflict loop, and captured epoch. One active verification per device. |
| `resolvedAccount`, `prior` | Account lookup result and receipt captured at verification start. Foreign receipts are discarded as offline evidence. |
| `observed`, `eligible`, `evidence`, `error` | Server response snapshot, sampled recording eligibility, observed/acknowledged version, and classified error. A response can be stale by delivery time. |
| `grantAccount`, `offlineReceipt` | Ghost provenance of the most recent grant. |
| `badPublisher`, `badServerDecrease` | Ghost history of an ineligible commit or decreasing server write. |
| `sawConflict`, `sawLostReply`, `sawOffline`, `sawAccountDuringRequest`, `sawViewerBaseline`, `sawReceiptFailure`, `sawRecovery`, `sawForeignReceipt` | Ghost reachability witnesses for the named scenarios. |

| Actions | Source region / suspension boundary |
| --- | --- |
| `Begin` | `refresh` creates one verification; `verify` loads its receipt and raises the local floor before account lookup. Repeated triggers join this task. |
| `ChangeAccount` | Observed account notification invalidates current access and marks an existing receipt blocked. |
| `ResolveAccount` | Account lookup returns or fails; mismatched prior receipt is discarded. |
| `Read`, `ReadReply` | Server fetch snapshot versus delivery and epoch check. The floor update, newer-version block, and synchronous blocked-receipt save form one main-actor action. |
| `Eligibility` | Return from the injected recording check, epoch validation, and decision to wait, save, or grant. |
| `PrepareSave`, `Commit` | Transport re-fetch/change-tag/version check followed by the separate conditional save. A competing writer can change the record between them. |
| `SaveReply` | Acknowledged save returns; epoch is checked before raising the local floor. A committed save with a lost response instead goes to `Fail`. |
| `Persist` | Atomic verified-receipt save and then allowed state; failure blocks access. |
| `Fail` | Current-epoch error handling: account-bound offline fallback or blocked state with a best-effort blocked receipt. |
| `Parked` | Idle/completed verifications, permitting stuttering without hiding a pending internal phase. |

Boot, foreground/poll, import notifications, push, Retry, and onboarding all
share this lane. Local-only builds do not use this protocol. Demo uses it with
ineligible recording; `InstallationLocation` supplies only real permission, and
demo scope events cannot change the receipt. The share
extension only reads the resulting receipt; its own open race is not modeled.

## Assumptions, properties, and bounds

Each device has a fixed build and fixed eligibility for a run. `Writers[d]`
abstracts local recording On, Always authorization, and a nonremoved identity
at publication admission. Disabled, permission-denied, and known-removed
installations and demo scopes all map to false. Consent/permission/removal/mode changes while an
eligibility lookup or save is suspended are **not** verified by this model.
An eligible publication request can commit after an observed account change;
its stale reply cannot grant local access.

Version doubles as the change tag because modeled writers only create or
increase this one-field record. This retains every conflict between these
writers; deletion/recreation, equal-version metadata edits, malformed records,
and arbitrary external writers are excluded. The server's conditional save is
assumed atomic. Subscription setup/backoff and additional transport account
checks are abstracted into failed requests. A canonical record is indexed by
its requested account; writes to a noncanonical record during a real account
switch are outside the model. Notification delay is not a guarantee of access
revocation before the app observes a change.

Receipt saves can fail during verification. `ChangeAccount` models successful
receipt invalidation; the foreign-receipt cold-start configuration independently
covers a still-verified account-A receipt with resolved account B. Process
crashes, torn/corrupt files, backup/entitlement behavior, and arbitrary external
receipt edits are excluded. The local monotonicity properties apply within a
modeled process, including repeated verifications, not across a crash that
loses an unpersisted observation.

All cases check `TypeOK`, `OnlyEligibleRecorderPublishes`,
`SharedVersionNeverDecreases`, `OnlineAdmissionHasServerEvidence`,
`ReceiptBeforeOnlineAdmission`, and `OfflineReceiptIsAccountBound`, plus the
action safety properties `KnownVersionNeverDecreases` and
`ReceiptVersionNeverDecreases`. Negative controls keep the same properties and
bounds as their matching current cases. Reachability cases add false
`...NotReached` invariants. No fairness, state constraints, symmetry reduction,
or liveness properties are used. Deadlock checks are enabled.

| Current config | Builds / eligibility | Shared initial version | Receipt seed | Refreshes/device |
| --- | --- | ---: | --- | ---: |
| `CurrentWriters.cfg` | 2, 3 / both eligible | 1 | absent | 1 |
| `CurrentRepeatedWriters.cfg` | 2, 3 / both eligible | 1 | absent | 2 |
| `CurrentViewer.cfg` | 2, 2 / viewer, recorder | absent | absent | 1 |
| `CurrentBaseline.cfg` | 1 / viewer | absent | absent | 2 |
| `CurrentReceipts.cfg` | 2 / viewer | 2 | verified A, version 2 | 2 |
| `CurrentHigherCache.cfg` | 2 / viewer | 1 | verified A, version 2 | 2 |
| `CurrentForeignReceipt.cfg` | 2 / viewer | 2 | verified A, version 2; current account B | 2 |

Each run has two accounts, versions 1–3, and at most one account invalidation
per device. Other configurations start on A. The retry loop retains its source
limit of three attempts, but these monotonic versions do not exercise three
successive conflicts. No claim about exhausting that budget is made.

## Counterexamples and Swift guards

All negative traces were inspected, including their final values:

- `broken-viewer`: a viewer reads an older/absent head, bypasses the recording
  check, and commits a higher version.
- `broken-save`: builds 2 and 3 both read version 1. Build 3 commits, then the
  unchecked build-2 write lowers the head. Both the refetch and final CAS matter.
- `broken-account`: successfully resolve account B with a verified A receipt,
  fail the read, then wrongly grant offline access. This is a known foreign
  account, not merely a failed account lookup.
- `broken-cache`: cached version 2 substitutes for a server version-1
  publication and admits a viewer without equal server evidence.
- `broken-receipt`: a successful server save is followed by a failed receipt
  write, but allowed is published anyway.

Relevant [DataCompatibilityCoordinatorTests](../../WhereCore/Tests/DataCompatibilityCoordinatorTests.swift)
include `onlyRecorderCanAdvanceAndWaitingViewerRecovers`,
`missingPermissionCannotAdvance`, `removedInstallationCannotPublishOnRelaunch`,
`uncertainUpgradeRequiresReadback`, `conflictWithNewerWriterBlocksInsteadOfDowngrading`,
`offlineAccessSurvivesRelaunchButNotAnUpgrade`,
`accountChangeRejectsSuspendedCompletion`, and
`higherCacheCannotSubstituteForSharedPublication`. They exercise the coordinator
with a scripted transport, not real CloudKit CAS. `receiptFailureDoesNotGrantAccess`
currently fails receipt **load**; the distinct post-save failure counterexample
is model-only coverage here. The account/receipt test suite and these models
are complementary, not an implementation refinement proof.
`WhereCompatibilityModelTests.recorderCanObtainPermissionAndPublishBeforeOpeningHistory`
and `demoCannotPublishOrBypassALockout` additionally guard the installation-level
eligibility adapter introduced by the 2026-11-17 review revision.

## Recorded run

2026-11-17 review revision: correspondence rechecked and all declared outcomes matched; every current case exhausted its
queue with no invariant, action-safety, or deadlock error. Negative and
reachability failures below are expected and inspected.

| Config | Expected result | Generated / distinct / depth |
| --- | --- | ---: |
| `CurrentWriters.cfg` | pass | 21,686 / 9,020 / 25 |
| `CurrentRepeatedWriters.cfg` | pass | 2,798,329 / 1,077,136 / 43 |
| `CurrentViewer.cfg` | pass | 10,592 / 4,323 / 18 |
| `CurrentBaseline.cfg` | pass | 615 / 369 / 14 |
| `CurrentReceipts.cfg` | pass | 667 / 403 / 14 |
| `CurrentHigherCache.cfg` | pass | 553 / 317 / 12 |
| `CurrentForeignReceipt.cfg` | pass | 781 / 474 / 14 |
| `BrokenViewer.cfg` | `OnlyEligibleRecorderPublishes` fails | 1,744 / 828 / 8 |
| `BrokenSave.cfg` | `SharedVersionNeverDecreases` fails | 11,767 / 5,188 / 15 |
| `BrokenAccount.cfg` | `OfflineReceiptIsAccountBound` fails | 26 / 23 / 5 |
| `BrokenCache.cfg` | `OnlineAdmissionHasServerEvidence` fails | 87 / 68 / 7 |
| `BrokenReceipt.cfg` | `ReceiptBeforeOnlineAdmission` fails | 4,280 / 1,910 / 10 |
| `Conflict.cfg` | `ConflictNotReached` fails | 9,568 / 4,240 / 14 |
| `LostReply.cfg` | `LostReplyNotReached` fails | 1,759 / 843 / 8 |
| `Offline.cfg` | `OfflineNotReached` fails | 26 / 23 / 5 |
| `AccountInFlight.cfg` | `AccountChangeDuringRequestNotReached` fails | 5 / 4 / 3 |
| `BaselineViewer.cfg` | `BaselineViewerNotReached` fails | 83 / 64 / 7 |
| `ReceiptFailure.cfg` | `ReceiptFailureNotReached` fails | 4,280 / 1,910 / 10 |
| `Recovery.cfg` | `RecoveryNotReached` fails | 211 / 153 / 8 |
| `ForeignReceipt.cfg` | `ForeignReceiptNotReached` fails | 6 / 5 / 3 |

Local run: `.build/tla/runs/CompatibilityPublication.qEL0mD/`; generated module:
`generated/CompatibilityPublication.tla`. Counts for expected failures are partial
searches ending at their first counterexample.

Tools: pinned `tla2tools` release 1.7.4 (TLC reports 2.19, revision `5a47802`),
PlusCal 1.11, Temurin Java 21.0.8+9. TLC artifact SHA-256:
`936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88`.
The runner retains generated translations, logs, state, and `summary.json`
under `.build/tla/runs/`, and checks that authored source was unchanged.
Recheck correspondence and rerun after implementation or model changes.
