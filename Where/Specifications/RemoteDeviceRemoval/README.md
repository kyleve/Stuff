# Remote device removal

This model checks one privacy-sensitive question: after one installation permanently removes
another, do independently synced advisory rows remain unable to reactivate the removed identity,
does the target eventually stop once it receives the tombstone, does every user-facing history
read hide that identity's GPS samples at and after the earliest delivered cutoff regardless of
arrival order, and can a later rejoin activate only a distinct identity?

The model represents the production behavior merged by [PR #160](https://github.com/kyleve/Stuff/pull/160)
at squash commit `60421db7`. It is evidence for the finite bounds and assumptions below, not proof
that the Swift implementation is correct.
Changes to removal persistence, CloudKit import notification, recording reconciliation, history
filtering, or rejoin identity rotation invalidate the result until this correspondence is checked.

## Source correspondence

| Model state or action | Production counterpart |
| --- | --- |
| `publishedRemovals` | Immutable [`RecordingDeviceRemoval`](../../WhereCore/Sources/Devices/RecordingDeviceRemoval.swift) tombstones available to CloudKit |
| `readerRemovals` / `targetRemovals` | Independently imported tombstones at a history-reading replica and the removed installation |
| `publishedAdvisories` / `readerAdvisories` | Separately synced `RecordingDeviceProfile`, target-owned `RecordingDeviceCheckIn`, and append-only `RecordingDeviceMetadataChange` rows |
| `readerLastOldEvent`| A deliberately broken whole-device/LWW design used only by the negative control. Current production never derives removal from arrival order || `readerSamples` | Old-identity GPS samples that may sync before or after any device row |
| `VisibleOldSamples` | [`LocationHistoryReader`](../../WhereCore/Sources/Devices/LocationHistoryReader.swift) applying `RecordingDeviceRemovalFilter.visibleSamples` on every user-facing read |
| `targetNotification` | The `WhereStore.changes()` ping forwarded after a CloudKit remote import |
| `reading` | [`DeviceRecordingController.applyObservedChange()`](../../WhereCore/Sources/Devices/DeviceRecordingController.swift) entering its exclusive lane and taking a generation-pinned policy snapshot |
| `revoking` | `reconcileLocked` has resolved a removal and is about to call `LocationIngestor.revokeRecordingAuthorization()` |
| `clearing` | Physical recording is stopped while `discardRetryBacklog()` durably removes queued old-identity samples |
| `retired` | The controller has published `.removed` and rejects the old identity as terminal |
| `activeIdentity = "new"` | `InstallationRecordingContextStoring.rejoin()` has persisted a fresh `RecordingDeviceID` after `retireForRejoin()` closed the old scope |

The modeled entry points are remote import delivery into the store, the controller's
`startMonitoringChanges()` observation path, `RecordingDeviceRemovalFilter.visibleSamples`, and
the explicit rejoin launch path. Removal creation, advisory publication, sample delivery, and
delivery to each replica are independent actions, so TLC explores their arbitrary interleavings.
Duplicate CloudKit materialization is abstracted as set insertion after the production store's
identity-based canonicalization. Malformed or conflicting immutable rows fail closed and are not.
modeled as valid protocol events.

The target path is split where production suspends: notification admission, snapshot resolution,
physical authorization revocation, and durable backlog discard. Weak fairness is applied only to
those four already-admitted controller phases: once the tombstone is persisted and its notification
is pending, the actor/exclusive lane, store read, ingestor stop, and backlog clear eventually return.
No fairness assumption claims that CloudKit eventually delivers a tombstone.

## Properties

- `TypeOK` checks every model variable.
- `RemovalDominatesAdvisoryState` requires a delivered append-only tombstone to remain effective
after profile, check-in, or metadata arrivals.
- `HistoryHonorsEarliestCutoff` requires every visible old-identity sample to precede the earliest
tombstone currently delivered to that reader.
- `RemovedIdentityNeverRestarts` requires the old physical recorder to remain Off after revocation.
- `RejoinCannotReviveRemovedIdentity` requires rejoin to occur only after retirement and durable
backlog clearing, without deleting the old tombstone or restarting the old recorder.
- `DistinctIdentityRecording` permits the new identity to record only while the old identity stays
stopped.
- `DeliveredRemovalEventuallyStops` and `DeliveredRemovalEventuallyRetires` require a target that
has received any tombstone eventually to revoke GPS and finish clearing its old backlog.
- The two reachability controls prove TLC exercised a late advisory plus an at/after-cutoff sample
through rejoin, and the order where a later cutoff arrives before the earliest cutoff.

Current configurations check deadlock freedom. The explicit quiescent stutter action represents a
live app after this finite scenario has delivered all bounded events and enabled the rejoined
identity.

## Wall-clock and cutoff assumption

`removedAt` and `LocationSample.timestamp` are wall-clock instants created on different devices.
The model represents them as integers around the cutoff and intentionally does **not** derive a
sample timestamp from action order. The verified history claim is exactly the production rule:
once a reader has the tombstone, samples whose recorded timestamp is greater than or equal to its
earliest `removedAt` are hidden.

This is not a causal-time guarantee. If the removed device's clock is behind the remover, a sample
captured causally after removal can carry a timestamp before the cutoff and remain visible. If its.
clock is ahead, a causally earlier sample can be hidden. The result therefore assumes the devices'
wall clocks are comparable enough for `removedAt` to be the desired privacy boundary. A protocol
requiring causal precision would need a server/causal boundary that production does not have.

## Bounds and exclusions

The old identity initially records and has a nonempty retry backlog. The checker exhausts:

| Configuration | Timestamp domain | Tombstone cutoffs | Result |
| --- | --- | --- | --- |
| `Current.cfg` | `0...2` | `{1}` | 22,631 generated / 4,888 distinct states, depth 19 |
| `CurrentMultiple.cfg` | `0...3` | `{1, 2}` | 678,105 generated / 113,648 distinct states, depth 23 |

Each configuration includes one profile, check-in, and metadata event. Every event and every sample.
timestamp is delivered at most once per replica. Set insertion represents idempotent duplicate
delivery. The model includes one removed identity, one distinct rejoin identity, two reader/target
replicas, a successful target policy read, and a successful backlog clear.

Unbounded devices/events, CloudKit non-delivery, corrupt/conflicting rows, store or outbox failure,
data-generation rotation, reset/import pause, authorization changes, process termination, and UI
caching are excluded. Production's fail-closed error paths and generation protocol have separate
tests/specifications. This model does not supply evidence for them.

## Controls and deterministic guards

`Broken.cfg` models the discarded architectural alternative where removal and advisory state share
one last-writer-wins device record. A check-in or metadata event delivered after the removal makes
the old identity effective again and violates `RemovalDominatesAdvisoryState` after 232 generated /
109 distinct states at depth 5.

`CurrentReachability.cfg` violates `CriticalScenarioNotReached` after 15,393 generated / 3,577
distinct states at depth 13, demonstrating that TLC reached a late advisory and at-cutoff sample,
then retired the old identity and enabled the new one. `CurrentReorderedCutoffReachability.cfg`
violates `EarlierCutoffNeverArrivesLate` after 625 generated / 282 distinct states at depth 5: cutoff
2 arrives first, then cutoff 1 becomes the effective earliest boundary. Both current safety/liveness
configurations exhaust their complete state spaces without an invariant, temporal-property, or
deadlock error.

**Verified for these model bounds and assumptions.**

The production obligations are guarded deterministically by:

- [`DeviceRecordingControllerTests.removalStopsCurrentIdentityAndPublishesTerminalState`](../../WhereCore/Tests/DeviceRecordingControllerTests.swift)
- [`WhereSessionTrackingTests.remoteRemovalStopsThisDevice`](../../WhereUI/Tests/WhereSessionTrackingTests.swift)
- [`RecordingDeviceRemovalFilterTests.hidesTargetSamplesAtAndAfterTheEarliestRemoval`](../../WhereCore/Tests/RecordingDeviceRemovalFilterTests.swift)
- [`ReportReaderTests.yearReportDetailsAppliesDeviceRecordingCutoffs`](../../WhereCore/Tests/ReportReaderTests.swift)
- [`SwiftDataStoreTests.removalTombstonesSurviveDataGenerationRotation`](../../WhereCore/Tests/SwiftDataStoreTests.swift)
- [`InstallationRecordingContextStoreTests.rejoinPersistsANewIdentityWithRecordingDefaultedOff`](../../WhereUI/Tests/InstallationRecordingContextStoreTests.swift)

## Run it

From the repository root:

```sh
./tla-check RemoteDeviceRemoval
```

The root checker pins TLC 1.7.4 by SHA-256 and Eclipse Temurin 21.0.8+9 through `mise`, caching both
under ignored `.build/tla/` storage. Checks are opt-in and are not wired into CI.
