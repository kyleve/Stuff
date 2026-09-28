# Automatic backup lifecycle

This model checks admission, cancellation, file commit, and scope retirement.
It also checks first-unlock preparation and late preference publication.
It supplies bounded protocol evidence, not a proof of Swift or iOS behavior.

## Source correspondence

| Model state or action | Swift boundary |
| --- | --- |
| `UnlockStep`, `LoadContextStep` | `FirstUnlockAvailability.waitUntilAvailable()` and `FileInstallationRecordingContextStore.prepareAfterFirstUnlock()` |
| `context` | Installation sidecar resolution before `WhereLaunch` reaches onboarding |
| `AdmitOrJoinStep`, `active` | `AutomaticBackupService.runIfDue` selects or creates its owned task without an intervening suspension |
| `DismissUIStep` | A Data-page caller uses `CallerCancellation.finishExecution` |
| `DisableStep`, `ExpireStep` | Configuration disable or an execution owner's cancellation cancels the shared task |
| `PrepareStep` | Cancellation checks between key access, snapshot loading, and archive staging |
| `WriteStep`, `committed` | The atomic file move in `AutomaticBackupStorage.write` |
| `RecordSuccessStep`, `successful` | The cancellation check and success timestamp after the storage call returns |
| `FinishMaintenanceStep` | Retention completes or reports failure without undoing export success |
| `ReleaseRunStep` | The joined caller clears the completed run by identity |
| `BeginRetirementStep`, `DrainStep` | Service shutdown cancels and awaits the run before scope replacement |
| `PublishPreferenceStep`, `generation` | `WherePreferences.recordAutomaticBackupSuccess` rejects an obsolete reset generation |

Each labelled process step is atomic. Separate steps permit cancellation or
retirement between operations. `WriteStep` may commit after cancellation was
requested: cancellation cannot revoke a file move already past its last check.
Retirement must therefore await completion, rather than merely request cancellation.

A disappearing view still awaits the shared result. It records successful
metadata before returning, but does not refresh the disappeared view.
It has no authority to cancel the shared export.

## Properties and bounds

The candidate configurations check all types and these safety properties:

- No installation-context read occurs before first unlock.
- UI disappearance cannot cancel the export.
- At most one admitted run has unfinished work.
- No file commit occurs after retirement returns.
- Every recorded success has a committed file.
- Published preferences belong to the current generation.
- Retirement returns only after all admitted work finishes.

`EventuallyReady` assumes the user eventually unlocks the device and context
loading succeeds. `EventuallyDrained` assumes admitted I/O eventually returns,
including cancellation acknowledgements. Neither property claims an iOS deadline.
Weak fairness applies only to those completion actions. User commands and
backup admission have no fairness assumption. `IdleStep` permits process stuttering.

The finite bounds are one installation, one retirement, one disable, one
expiration, one UI caller, and one or two admitted runs.
Calendar scheduling, onboarding choices, failed reset resumption, and a newly
created scope are excluded. Store transactions and cryptography are abstracted.
Tests, not this model, check scheduler revisions and exact interval calculations.

## Controls and results

The checked candidate state spaces on 2026-09-07 were:

| Case | Generated / distinct states | Depth |
| --- | ---: | ---: |
| `candidate` | 1,722 / 486 | 17 |
| `candidate-two-runs` | 16,420 / 4,066 | 25 |

`review-ui` and `review-unlock` reproduce the reviewed cancellation and eager
sidecar-load defects. `broken-drain` permits retirement before the write returns.
`broken-generation` permits an old caller to publish after reset.
Each negative control must violate its named safety invariant.

The reachability control must find an in-flight retirement with a committed
file. Its expected failure proves that this boundary is reachable.
The manifest records the expected result of every case.

Swift regression coverage includes `FirstUnlockAvailabilityTests`,
`InstallationRecordingContextStoreTests`, `PrepareProtectedDataStepTests`,
`AutomaticBackupServiceTests`, and `BackupModelTests`.

## Run

```sh
./tla-check AutomaticBackupLifecycle
```

The checker retains translations, logs, state counts, and tool checksums in
`.build/tla/runs/`. See the [specification workflow](../README.md).
Recheck this mapping after changing any corresponding Swift boundary.
