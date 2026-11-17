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

Source baseline: `04cb13b2cf83b01e617f3f0bd569d2c7aec2dd6a`, with the
`WhereCompatibilityModel.bind` recovery fix committed alongside this model.
The publication/receipt protocol is checked separately in
[CompatibilityPublication](../CompatibilityPublication/README.md).

The admission point is the synchronous access check before launching a store
open. An open already in flight may finish physically; its result must pass
the scope epoch and current access checks before installation. Lockout masks
history immediately, while GPS stop, launch drain, onboarding drain, and scope
release remain separate actions. Release and completion of the task awaiting
`LifecycleRunner.teardown` are also separate: that task awaits the recovery
launch, including detached work.

| Model state | Production fact |
| --- | --- |
| `accountEpoch`, `decision`, `decisionEpoch` | [DataCompatibilityCoordinator](../../WhereCore/Sources/Compatibility/DataCompatibilityCoordinator.swift): account invalidation, access state, and verification epoch. Allowed includes a valid offline decision. |
| `checks`, `currentCheck`, `checkPhase`, `checkEpoch` | Coalesced verification task plus canceled tasks whose async work can still return. Bounded slots represent task identities. |
| `scopeEpoch`, `scopes`, `opening`, `active`, `scopePhase`, `openingEpoch` | [WhereModel.resolveScope/logOut](../../WhereUI/Sources/Model/WhereModel.swift) and [WhereBootstrap.prepareStore](../../WhereUI/Sources/Launch/WhereLaunch.swift): one opening task, active scope, captured generation, discarded results, and release. An `opening` counts conservatively as a live container. |
| `owner`, `callerDone` | Launch or process-owned onboarding work retaining the scope across awaits. Joining coalesced callers is abstracted into the last caller's completion. |
| `retirement` | Stop, serialized launch drain, epoch invalidation, onboarding shutdown/drain, and logout. |
| `tasks`, `taskOwner`, `taskPhase` | [WhereCompatibilityModel.retirement](../../WhereUI/Sources/Compatibility/WhereCompatibilityModel.swift): latest task, canceled predecessors, and a task still awaiting recovery after scope release. |
| `retired`, `commandedGPS`, `physicalGPS`, `pendingStop`, `gpsPhase` | [DeviceRecordingController.shutdown](../../WhereCore/Sources/Devices/DeviceRecordingController.swift), [LocationIngestor.start/retire](../../WhereCore/Sources/Location/LocationIngestor.swift): terminal retirement, `isMonitoring`, actual location-source effect, pending stop, and suspended authorization/start. |
| `badOpen`, `badInstall`, `badGPS` | Ghost history of forbidden admissions. They retain a bad event even if a later operation repairs the state. |
| `staleCheckRejected`, `staleOpenRejected`, `staleScopeEpochRejected`, `blockedOpening`, `pendingRetiredGPS`, `didRelease`, `recovered`, `failedOpen`, `repeatedLockout` | Ghost reachability witnesses. `didRelease` requires an actual active scope; recovery witnesses cannot pass by retiring an empty launch. |

Every process label is one modeled atomic boundary. Assignments using `||`
read the same pre-state.

| Actions | Source region / suspension boundary |
| --- | --- |
| `BeginCheck`, `CompleteCheck`, `AccountChange` | Coordinator task creation, return from verification with `checkEpoch`, and account notification. Compatible/blocked results abstract the separate publication model. |
| `RequestRetirement` macro | Synchronous state-change callback schedules the newest task and cancels its predecessor, distinguishing cancellation before task entry. `retainedTask` reproduces the old `retirement == nil` condition. |
| `BeginOpen`, `CompleteOpen`, `DiscardOpen` | `resolveScope` access check, awaited assembly followed by epoch/access checks, then shutdown and disposal of a rejected result. Internal assembly awaits that do not grant access are collapsed into the open interval. |
| `BeginGPS`, `AuthorizeGPS` | Recording request and post-authorization/outbox/output check before commanding monitoring. |
| `PhysicalStart`, `StartReturns`, `StopLateStart` | Location source start effect, return to the ingestor, and compensating stop when retirement crossed that await. A submitted start can take effect after the first stop. |
| `StopBeforeDrain`, `StopHardware` | Controller closes admission and retires the ingestor before joining recording/launch work. The hardware stop is a separate await. |
| `FinishCaller`, `InvalidateScope` | [LifecycleRunner.teardownErased](../../../Shared/LifecycleKit/Sources/LifecycleRunner.swift) joins the launch drive; `shutdownForCompatibility` then increments the scope epoch and cancels onboarding. |
| `StopAfterInvalidation`, `ReleaseScope` | Shutdown also covers a scope assembled during the initial launch drain, joins onboarding/recording work, then logs out. Release itself does **not** stop hardware. |
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
`AdmissionRequiresCurrentDecision`, `NoStaleScopeInstallation`,
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

The other inspected negative traces remove one class of guard:

- `broken-admission`: open while still checking.
- `broken-verification`: account changes, then an old check publishes allowed.
- `broken-opening`: lockout crosses assembly, then its result installs.
- `broken-scope-epoch`: onboarding assembly finishes after invalidation and a
  new allowed decision; checking access alone admits the obsolete scope.
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
shutdown suites. Those are complementary checks, not an executable refinement
proof. In particular, `shutdownRejectsPhysicalStartAfterSuspendedOutput` checks
the **pre-start** guard, not a hardware start suspended after invocation; that
latter negative trace is model-only coverage here.

## Recorded run

2026-11-17: all declared outcomes matched; every current case exhausted its
queue with no invariant or deadlock error. Negative and reachability failures
below are expected and inspected.

| Config | Expected result | Generated / distinct / depth |
| --- | --- | ---: |
| `Current.cfg` | pass | 13,449 / 6,768 / 24 |
| `CurrentMoreChecks.cfg` | pass | 29,003 / 12,512 / 24 |
| `CurrentMoreAccounts.cfg` | pass | 69,782 / 32,407 / 30 |
| `CurrentRepeatedRecovery.cfg` | pass | 722,083 / 289,088 / 33 |
| `BrokenVerification.cfg` | `CurrentDecisionOnly` fails | 12 / 10 / 4 |
| `BrokenOpening.cfg` | `NoStaleScopeInstallation` fails | 90 / 70 / 6 |
| `BrokenGPS.cfg` | `RetiredScopeCannotReauthorizeGPS` fails | 837 / 514 / 9 |
| `BrokenRelease.cfg` | `ReleaseBeforeReplacement` fails | 3,156 / 1,780 / 12 |
| `StaleVerification.cfg` | `StaleVerificationNotReached` fails | 11 / 9 / 4 |
| `OpeningLockout.cfg` | `OpeningLockoutNotReached` fails | 90 / 70 / 6 |
| `RetiredPendingGPS.cfg` | `RetiredPendingGPSNotReached` fails | 449 / 294 / 8 |
| `Recovery.cfg` | `RecoveryNotReached` fails | 7,340 / 3,900 / 15 |
| `FailedOpen.cfg` | `FailedOpenNotReached` fails | 41 / 32 / 5 |
| `BrokenRecovery.cfg` | `BlockedScopeHasRetirement` fails | 15,051 / 7,608 / 14 |
| `BrokenLateGPS.cfg` | `ReleasedScopeHasNoGPS` fails | 28,981 / 14,161 / 16 |
| `RepeatedLockout.cfg` | `RepeatedLockoutNotReached` fails | 34,103 / 16,450 / 17 |
| `BrokenAdmission.cfg` | `AdmissionRequiresCurrentDecision` fails | 4 / 4 / 2 |
| `BrokenScopeEpoch.cfg` | `NoStaleScopeInstallation` fails | 2,211 / 1,277 / 11 |
| `StaleScopeEpoch.cfg` | `StaleScopeEpochNotReached` fails | 890 / 543 / 9 |
| `BrokenLateRetirement.cfg` | `NoObsoleteTaskRetiresReplacement` fails | 162,377 / 70,178 / 17 |

Local run: `.build/tla/runs/CompatibilityLockout.0XJ4hO/`; generated module:
`generated/CompatibilityLockout.tla`. Counts for expected failures are partial
searches ending at their first counterexample.

Tools: pinned `tla2tools` release 1.7.4 (TLC reports 2.19, revision `5a47802`),
PlusCal 1.11, Temurin Java 21.0.8+9. TLC artifact SHA-256:
`936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88`.
Generated translations and logs stay in `.build/tla/runs/`; the checker verifies
that the authored module is unchanged. Production or model changes require
checking correspondence and rerunning the model.
