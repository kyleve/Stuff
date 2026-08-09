# Tracking reconciliation TLA+ pilot

This model checks one narrow question about automatic-recording commands: after a finite sequence
of local enable/disable choices and all asynchronous work settles, do the installation sidecar,
Core controller, real ingestor, and published UI state all describe the latest choice?

The model represents the final recording-command design from PR #160. It is design evidence for
the stated bounds and assumptions, not proof that the Swift implementation is correct. Relevant
changes to the recording command, permission, controller-serialization, or publication paths
invalidate the result until this mapping is checked again.

## Source correspondence

| Model state or action | Production counterpart |
| --- | --- |
| `submitted` | The latest command's monotonic `WhereSession.recordingIntentSequence` |
| `desired` | The Boolean value carried by that latest `setRecordingEnabled(_:)` call |
| `persisted` | The installation-local choice written synchronously to `InstallationRecordingContextStoring` before the first suspension |
| `permission` phase | An enable command suspended in `LocationIngestor.requestPermission()` and `syncAuthorization()` |
| Stale permission rejection | The sequence guard immediately after the permission suspension |
| `queue` / `inFlight` | Calls waiting at, or holding, `DeviceRecordingController.beginExclusive()` |
| `controllerChoice` | `DeviceRecordingController.automaticRecordingEnabled` |
| `target` | The in-flight choice gated by the controller call's resolved authorization |
| `ingestorActive` | `LocationIngestor.isActive` after the physical transition |
| `published` | `WhereSession.isTracking`, derived from the controller's ordered runtime update |
| `CurrentBegin` | The controller admits the FIFO head and begins its store/physical transition |
| `CurrentComplete` | The exclusive controller transition succeeds and its runtime state is applied |

The source entry points represented are `WhereSession.startTracking()`, `stopTracking()`, and
`setRecordingEnabled(_:)`. Launch, foreground, authorization observation, and CloudKit-change
reconciliation also enter the controller's exclusive lane, but do not change local consent; the
model permits them to delay a command without representing their choice-neutral work. Onboarding
registration happens before an active session can submit these commands and is outside this
protocol.

The model splits the implementation at the permission suspension and the cross-actor controller
entry. It treats the controller's full transition as exclusive across its store, outbox, ingestor,
and check-in awaits, matching `beginExclusive()` / `endExclusive()`. Queue order is FIFO. Runtime
publication is abstracted into the successful transition completion: production additionally
orders emissions and ignores an update whose sequence is no newer than the last applied one.

## Properties

- `TypeOK` checks every model variable.
- `CurrentIntentIsImmediate` requires the sidecar choice to match the latest submitted command,
  including while permission or a Core transition is suspended.
- `CorrectAtQuiescence` requires sidecar and controller intent to equal the latest command, and the
  ingestor and UI state to equal that intent gated by authorization.
- `EventuallySettled` requires those facts to converge after the finite command list is submitted.
- `StalePermissionNotObserved` is deliberately violated by the reachability check, proving that TLC
  explored the branch where an older enable completes after a newer command.
- Candidate configurations check deadlock freedom. The explicit quiescent stutter action models a
  live process after this finite protocol has settled.

Weak fairness assumes each configured command is eventually submitted, permission requests return,
and an admitted Core transition eventually completes. These correspond to the runtime progress
guarantees needed only for `EventuallySettled`; the safety invariants do not depend on fairness.

## Bounds and exclusions

The initial choice is Off. The checker exhausts these finite configurations:

| Configuration | Commands | Authorized | Generated / distinct states | Depth |
| --- | --- | --- | --- | --- |
| `Current.cfg` | enable, disable | true | 22 / 16 | 8 |
| `CurrentDenied.cfg` | enable, disable | false | 22 / 16 | 8 |
| `CurrentRepeated.cfg` | enable, enable, disable | true | 96 / 56 | 12 |
| `CurrentReversed.cfg` | disable, enable | true | 17 / 12 | 8 |

The model abstracts authorization to the value observed after permission returns. Permission
failure therefore takes the same state path as a returned unauthorized result. Store/outbox/check-in
failure, task cancellation, reset/import pause, device removal, process termination, GPS samples,
and unbounded command streams are excluded. Those paths fail closed or have separate lifecycle
contracts and are not evidence supplied by this pilot.

## Controls and result

`Broken.cfg` retains the old independent-task design as a negative control. TLC violates
`CorrectAtQuiescence` after 33 generated / 26 distinct states at depth 8: enable starts, disable
stops and publishes Off, then the older enable completion publishes On while persisted intent and
the ingestor remain Off.

`CurrentStaleReachability.cfg` deliberately asserts that stale rejection was never observed. TLC
violates it after 5 generated / 5 distinct states at depth 4, demonstrating that the important
permission-race branch is reachable rather than vacuous. All four current configurations then
exhaust their complete state spaces without an invariant, temporal-property, or deadlock error.

The deterministic software guard is
`WhereSessionTrackingTests.offWinsWhileAnEarlierEnableWaitsForPermission`. It parks the real
permission seam, submits Off, releases the older enable, and checks the sidecar-facing device
configuration, advisory status, and UI tracking state.

## Run it

From the repository root:

```sh
./tla-check TrackingReconciliation
```

Or run every spec: `./tla-check`. See `./tla-check --help` for options.

The checker pins TLC 1.7.4 by SHA-256 and Eclipse Temurin 21.0.8+9 through
`mise`. It caches both under the repository's ignored `.build/tla/` directory.
A clean first run needs network access and downloads about 350 MB, almost all of
it the JDK. Each run keeps its TLC log and state under `.build/tla/runs/`. A
successful run means both negative controls failed for their expected invariants
and every current model completed without an error. Checks are opt-in and are not wired
into CI.
