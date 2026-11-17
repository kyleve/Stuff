# Compatibility lockout

Can an obsolete completion or a second lockout admit an incompatible scope,
leave a blocked scope without retirement, or restart a retired scope's GPS?

**Verified for these model bounds and assumptions**, after fixing the recovery
task race described below. The original task handling is **falsified** by
`BrokenRecovery.cfg` and a deterministic Swift regression. This is bounded
protocol evidence, not proof of the Swift implementation or CloudKit delivery.

Run from the repository root:

```sh
./tla-check CompatibilityLockout
```

## Boundary and source correspondence

Original source baseline: `04cb13b2cf83b01e617f3f0bd569d2c7aec2dd6a`, with the
`WhereCompatibilityModel.bind` recovery fix in `c8eb66ecb`/`fd31d5a02`.
The 2026-11-17 review revision replaces the stored scope epoch with an opening
object identity and explicit startup states; the unified-access follow-up also binds store openings and real scopes to a domain/epoch admission. Correspondence was rechecked below.
The publication/receipt protocol is checked separately in
[CompatibilityPublication](../CompatibilityPublication/README.md).

The admission point is the synchronous access check before launching a store
open. An open already in flight may finish physically; its result must pass
the current opening identity and access checks before installation. Lockout masks
history immediately, while GPS stop, launch drain, onboarding drain, and scope
release remain separate actions. Release and completion of the task awaiting
`LifecycleRunner.teardown` are also separate: that task awaits the recovery
launch, including detached work.

| Model state | Production fact |
| --- | --- |
| `accountEpoch`, `decision`, `decisionEpoch` | [DataCompatibilityCoordinator](../../WhereCore/Sources/Compatibility/DataCompatibilityCoordinator.swift): account invalidation, access state, and verification epoch. Allowed includes a valid offline decision. |
| `admissionGeneration`, `openingAdmission` | Admission token invalidation on account changes and every allowed-to-blocked withdrawal, captured when opening begins. Numeric increments abstract token inequality; the Swift counter may advance more than once per notification. |
| `checks`, `currentCheck`, `checkPhase`, `checkEpoch` | Coalesced verification task plus canceled tasks whose async work can still return. Bounded slots represent task identities. |
| `scopeEpoch`, `scopes`, `opening`, `active`, `scopePhase`, `openingEpoch` | [WhereModel.resolveScope/retireScope](../../WhereUI/Sources/Model/WhereModel.swift), [WhereStartupState](../../WhereUI/Sources/Model/WhereStartupState.swift), and [WhereBootstrap.prepareStore](../../WhereUI/Sources/Launch/WhereLaunch.swift): one identified opening, active scope/session, retired owner, discarded results, and release. The numeric epoch abstracts equality of the current opening object; it is no longer a stored Swift counter. Every coalesced waiter checks access before returning. The domain/epoch token additionally rejects pre-invalidation work after the same account recovers; an active stale scope remains masked until retirement. An `opening` counts conservatively as a live container. |
| `owner`, `callerDone` | Launch or process-owned onboarding work retaining the scope across awaits. Joining coalesced callers is abstracted into the last caller's completion. |
| `retirement` | Stop, serialized launch drain, replacing startup with retiring, onboarding shutdown/drain, and release. |
| `tasks`, `taskOwner`, `taskPhase` | [WhereCompatibilityModel.retirement](../../WhereUI/Sources/Compatibility/WhereCompatibilityModel.swift): latest task, canceled predecessors, and a task still awaiting recovery after scope release. |
| `retired`, `commandedGPS`, `physicalGPS`, `pendingStop`, `gpsPhase` | [DeviceRecordingController.shutdown](../../WhereCore/Sources/Devices/DeviceRecordingController.swift), [LocationIngestor.start/retire](../../WhereCore/Sources/Location/LocationIngestor.swift): terminal retirement, `isMonitoring`, actual location-source effect, pending stop, and suspended authorization/start. |
| `badOpen`, `badInstall`, `badGPS` | Ghost history of forbidden admissions. They retain a bad event even if a later operation repairs the state. |
| `staleCheckRejected`, `staleOpenRejected`, `staleScopeEpochRejected`, `blockedOpening`, `pendingRetiredGPS`, `didRelease`, `recovered`, `failedOpen`, `repeatedLockout` | Ghost reachability witnesses. `didRelease` requires an actual active scope; recovery witnesses cannot pass by retiring an empty launch. |

`active` includes a scope captured by the retirement task even after the public
`model.activeScope` projection becomes nil. The log-opening task and bootstrap
retry waiters are not separate model processes: their ownership is abstracted
into completion/release readiness and opening identity. The held-log Swift
regression checks log-task drain; bootstrap coalesced retry identity/return guards
were source-reviewed, and their individual waiter interleavings are not explored
by this model.

Every process label is one modeled atomic boundary. Assignments using `||`
read the same pre-state.

| Actions | Source region / suspension boundary |
| --- | --- |
| `BeginCheck`, `CompleteCheck`, `AccountChange` | Coordinator task creation, return from verification with `checkEpoch`, and observed domain invalidation (notification or refresh discovery). Compatible/blocked results abstract the separate publication model. |
| `RequestRetirement` macro | Synchronous state-change callback schedules the newest task and cancels its predecessor, distinguishing cancellation before task entry. `retainedTask` reproduces the old `retirement == nil` condition. |
| `BeginOpen`, `CompleteOpen`, `DiscardOpen` | `resolveScope` access check, awaited assembly followed by opening-identity/access checks, then shutdown and disposal of a rejected result. Internal assembly awaits that do not grant access are collapsed into the open interval. |
| `BeginGPS`, `AuthorizeGPS` | Recording request and post-authorization/outbox/output check before commanding monitoring. |
| `PhysicalStart`, `StartReturns`, `StopLateStart` | Location source start effect, return to the ingestor, and compensating stop when retirement crossed that await. A submitted start can take effect after the first stop. |
| `StopBeforeDrain`, `StopHardware` | Controller closes admission and retires the ingestor before joining recording/launch work. The hardware stop is a separate await. |
| `FinishCaller`, `InvalidateScope` | [LifecycleRunner.teardownErased](../../../Shared/LifecycleKit/Sources/LifecycleRunner.swift) joins the launch drive; `shutdownForCompatibility` cancels onboarding and replaces startup ownership with a retirement task, invalidating any prior opening identity. |
| `StopAfterInvalidation`, `ReleaseScope` | Shutdown also covers a scope assembled during the initial launch drain, joins onboarding/recording work and the scope-owned log-opening task, then publishes locked or fresh preparation. Release itself does **not** stop hardware. |
| `FinishRetirementTask` | Return from teardown's recovery launch, or a canceled predecessor returning late. Only the current task may clear the handle. |
| `LateCanceledTask` | Negative control only: removing the task-entry cancellation check lets an obsolete queued task retire the current replacement scope. |
| `Parked` | Idle, ready, or blocked gate with no modeled work outstanding; intentional stuttering. |

Boot, foreground/poll, remote imports, CloudKit push, Retry, discovery, and
onboarding Finish enter the same coordinator. The model treats refresh triggers
as interchangeable and coalesces callers of a current verification/open. It
represents one retaining launch or onboarding caller per scope, not every UI
task or import operation. Onboarding completion cannot itself change the
coordinator decision; its cancellation and scope retention participate in drain.

## Properties and bounds

All configurations check `TypeOK`, `CurrentDecisionOnly`,
`AdmissionRequiresCurrentDecision`, `NoStaleScopeInstallation`, `NoStaleAdmissionInstallation`,
`ReleaseBeforeReplacement`, `RetiredScopeCannotReauthorizeGPS`,
`ReleasedScopeHasNoGPS`, `BlockedScopeHasRetirement`, and
`NoObsoleteTaskRetiresReplacement`. Negative controls use
the same properties and bounds as the corresponding current configurations.
Reachability cases add an intentionally false `...NotReached` invariant.

| Current config | Checks | Scopes | Observed account changes |
| --- | ---: | ---: | ---: |
| `Current.cfg` | 2 | 2 | 1 |
| `CurrentMoreChecks.cfg` | 3 | 1 | 1 |
| `CurrentMoreAccounts.cfg` | 2 | 2 | 2 |
| `CurrentRepeatedRecovery.cfg` | 3 | 2 | 2 |

There are no state constraints, symmetry reductions, or fairness assumptions.
TLC checks safety and deadlocks; no eventual delivery, stop latency, or eventual
recovery claim is made. Suspended work can remain suspended indefinitely.
`Parked` permits only quiescent stuttering, not stuttering over a stuck internal
phase. Successful and failed opens, late verification/open/start completions,
repeated invalidation, and recovery are nondeterministic.

Excluded: unobserved remote incompatibility, atomic ordering between metadata
and SwiftData imports, cancellation of every already admitted data API,
cross-process share-extension admission, demo/reset/import internals, and
foreground promotion superseding teardown. Scope references held by arbitrary
external consumers are outside the ownership model. Physical start may briefly
finish after retirement; the checked boundary is reauthorization and completed
scope release, not instantaneous hardware stop at notification delivery.

## Counterexamples and Swift guards

The recovery counterexample retains a task in `relaunch`, opens a new scope,
then observes another block. The old `retirement == nil` guard suppresses a
new retirement, violating `BlockedScopeHasRetirement` with an active scope.
In source, [the callback](../../WhereUI/Sources/Compatibility/WhereCompatibilityModel.swift#L46)
held its task until `launcher.teardown` returned; [the runner](../../../Shared/LifecycleKit/Sources/LifecycleRunner.swift#L189)
awaited the entire recovery launch. The fix cancels/supersedes that task on
every allowed-to-blocked transition. Cancellation checks at task entry, before
teardown, and before clearing the handle reject late predecessors. Checking at
entry matters: a canceled unstructured task may first run after a replacement
scope is already allowed, and must not stop that scope.

`WhereCompatibilityModelTests.lockoutDuringRecoveryRetiresTheReplacementScope`
holds a detached recovery step after ready, while the replacement scope tracks.
A second failed verification must stop GPS before that step is released, then
release the session and store. It failed on the original code (no second
teardown) and passed after the fix, with the other 77 selected tests. The hold
uses a continuation, not a timed delay.

The inspected negative traces remove one class of guard:

- `broken-admission`: open while still checking.
- `broken-verification`: account changes, then an old check publishes allowed.
- `broken-opening`: lockout crosses assembly, then its result installs.
- `broken-opening-admission`: an opening begins, admission is withdrawn, a fresh decision allows access, and the old opening installs before owner invalidation. Removing the captured admission check violates `NoStaleAdmissionInstallation` even though the opening object remains current.
- `broken-release`: recovery opens while the previous container is retained.
- `broken-gps`: authorization starts again after terminal retirement.
- `broken-late-gps`: start was issued before retirement, takes effect after
  stop, and the removed post-start cleanup leaves hardware active at release.
- `broken-late-retirement`: a canceled task first enters after a newer
  retirement/recovery, then shuts down the replacement scope. The entry check
  added during review prevents this; its adversarial scheduling is model-only
  coverage here.

Existing Swift coverage includes `accountChangeRejectsSuspendedCompletion`,
`blockedLaunchAndDiscoveryNeverOpenHistory`, `waitingViewerRecoversWithOneFreshScope`,
`runningLockoutReleasesStoreAndPreservesConsent`, and the ingestor/controller
shutdown suites. The review revision adds `retirementDiscardsAnOpenBeforeReplacement` and makes `DemoModeTests.aLogStoreOpeningLateNeverAttachesToAShadowedScope` hold retirement until the log-open task drains. Those are complementary checks, not an executable refinement
proof. In particular, `shutdownRejectsPhysicalStartAfterSuspendedOutput` checks
the **pre-start** guard, not a hardware start suspended after invocation; that
latter negative trace is model-only coverage here.

`BrokenScopeEpoch.cfg` is now an expected-pass redundancy control: removing only the opening-owner guard no longer admits a stale result, because every owner invalidation in this bounded model also revokes admission. The older model found a counterexample with that variant; the new token closes it. Production keeps both guards because logout/reset and arbitrary ownership changes are outside this model. `StaleScopeEpoch.cfg` still witnesses owner-stale rejection.

Independent review found that the first follow-up model had not captured the admission generation. The extension now checks it across both account changes and ordinary blocked/recovered decisions; the new negative trace and witness reach the suspended-opening boundary before owner invalidation.

## Recorded run

2026-11-17 review revision: correspondence rechecked and all declared outcomes matched; every current case exhausted its
queue with no invariant or deadlock error. Negative and reachability failures
below are expected and inspected.

| Config | Expected result | Generated / distinct / depth |
| --- | --- | ---: |
| `Current.cfg` | pass | 13,656 / 6,913 / 24 |
| `CurrentMoreChecks.cfg` | pass | 28,107 / 12,240 / 24 |
| `CurrentMoreAccounts.cfg` | pass | 67,517 / 31,485 / 30 |
| `CurrentRepeatedRecovery.cfg` | pass | 709,788 / 290,644 / 33 |
| `BrokenVerification.cfg` | `CurrentDecisionOnly` fails | 12 / 10 / 4 |
| `BrokenOpening.cfg` | `NoStaleScopeInstallation` fails | 90 / 71 / 6 |
| `BrokenGPS.cfg` | `RetiredScopeCannotReauthorizeGPS` fails | 865 / 542 / 9 |
| `BrokenRelease.cfg` | `ReleaseBeforeReplacement` fails | 3,413 / 1,944 / 12 |
| `StaleVerification.cfg` | `StaleVerificationNotReached` fails | 11 / 9 / 4 |
| `OpeningLockout.cfg` | `OpeningLockoutNotReached` fails | 90 / 71 / 6 |
| `RetiredPendingGPS.cfg` | `RetiredPendingGPSNotReached` fails | 457 / 307 / 8 |
| `Recovery.cfg` | `RecoveryNotReached` fails | 7,962 / 4,266 / 15 |
| `FailedOpen.cfg` | `FailedOpenNotReached` fails | 41 / 32 / 5 |
| `BrokenRecovery.cfg` | `BlockedScopeHasRetirement` fails | 15,874 / 8,140 / 14 |
| `BrokenLateGPS.cfg` | `ReleasedScopeHasNoGPS` fails | 29,898 / 14,732 / 16 |
| `RepeatedLockout.cfg` | `RepeatedLockoutNotReached` fails | 36,292 / 17,589 / 17 |
| `BrokenAdmission.cfg` | `AdmissionRequiresCurrentDecision` fails | 4 / 4 / 2 |
| `BrokenScopeEpoch.cfg` | pass | 13,656 / 6,913 / 24 |
| `StaleScopeEpoch.cfg` | `StaleScopeEpochNotReached` fails | 917 / 569 / 9 |
| `BrokenLateRetirement.cfg` | `NoObsoleteTaskRetiresReplacement` fails | 174,235 / 76,747 / 17 |
| `BrokenOpeningAdmission.cfg` | `NoStaleAdmissionInstallation` fails | 1,014 / 705 / 8 |
| `StaleAdmission.cfg` | `StaleAdmissionNotReached` fails | 1,014 / 705 / 8 |

Local run: `.build/tla/runs/CompatibilityLockout.DbwL0F/`; generated module:
`generated/CompatibilityLockout.tla`. Counts for expected failures are partial
searches ending at their first counterexample.

Tools: pinned `tla2tools` release 1.7.4 (TLC reports 2.19, revision `5a47802`),
PlusCal 1.11, Temurin Java 21.0.8+9. TLC artifact SHA-256:
`936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88`.
Generated translations and logs stay in `.build/tla/runs/`; the checker verifies
that the authored module is unchanged. Production or model changes require
checking correspondence and rerunning the model.

`WhereCompatibilityModelTests.recoveryCannotAdmitAnOpeningFromBeforeInvalidation` covers both same-account invalidation and failed-verification recovery. `recoveringAccessCannotRevealOrReuseThePreviousScope` guards active-scope reuse and masking. The model does not separately render UI or enumerate storage modes; local/cloud evidence is checked in the publication model.
