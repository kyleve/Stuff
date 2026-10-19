# Location quarantine plan

Status: design plan

This document defines a general location-quarantine system for Where. Flight
detection is the first quarantine method. The design does not restrict the
system to flights.

The quarantine system uses public platform APIs. It does not read Airplane
Mode or use a private framework.

## Goals

- Keep suspect location samples out of visible history until Where resolves
  their quarantine state.
- Store samples and quarantine records in the regular SwiftData store.
- Sync quarantine records, samples, and decisions through CloudKit.
- Let more than one quarantine method classify the same sample.
- Let the user keep or ignore each quarantine independently.
- Preserve accepted and ignored samples for provenance, backup, and conflict
  recovery.
- Make all devices converge after offline or concurrent decisions.
- Keep reports, widgets, forecasts, and data-issue scans free of hidden
  samples.
- Add flight detection without adding private APIs or new dependencies.

## Non-goals

- The first version does not detect Airplane Mode.
- The first version does not use network state as a flight signal.
- The first version does not use Core Location speed or altitude fields.
- The first version does not expose a runtime plug-in API for quarantine
  methods.
- The first version does not let the user undo an ignored quarantine.
- A confirmed quarantine does not expire automatically.

## Product behavior

Automatic tracking stays active during a suspected flight. Where stores each
suspect sample immediately, but Where does not show a blocking sample in
history.

Where confirms a flight after it observes sustained flight-speed movement. It
then adds one review to Resolve. If notification permission exists, the
detecting device also sends an immediate notification.

The user has two decisions:

- **Keep Locations** makes the samples visible. Their accepted quarantine
  provenance remains in the store.
- **Ignore In-Flight Locations** keeps the samples in the store. The samples
  remain hidden from history.

The generic decision names are Keep and Ignore. Each quarantine method can
provide more specific user-facing text.

Pending reviews sync to all devices. Only the detecting device sends the
immediate notification.

## Domain model

### `LocationQuarantineID`

`LocationQuarantineID` is a dedicated UUID-backed identifier. It conforms to
`Hashable`, `Codable`, and `Sendable`.

### `LocationQuarantineMethod`

`LocationQuarantineMethod` is an exhaustive raw-value enum. The first case is
`.flight`.

The persisted raw value is stable. A Swift case rename must not change that
raw value.

Each method owns these items:

- A detector.
- Method-specific detail data.
- Notification text.
- Resolve presentation.
- A method-specific alert preference, when necessary.
- Method-specific unit and snapshot coverage.

### `LocationQuarantineDisposition`

Each sample membership has one disposition:

| Disposition | Blocks visibility | Meaning |
| --- | --- | --- |
| `candidate` | Yes | A detector needs more evidence. |
| `pending` | Yes | The method confirmed the quarantine. |
| `accepted` | No | The user chose Keep. |
| `ignored` | Yes | The user chose Ignore. |
| `released` | No | The detector withdrew an unconfirmed candidate. |

The raw values are stable persisted values.

### `LocationQuarantine`

The common quarantine value contains:

- The quarantine ID.
- The method.
- The detecting device ID.
- The detection timestamp.
- The first and latest sample timestamps.
- An optional confirmation timestamp.
- An optional closure timestamp.
- An optional release timestamp for a canceled candidate.

Method-specific facts do not become optional fields on this common type.

### `LocationQuarantineMembership`

A membership links one sample to one quarantine. It contains:

- A stable membership ID.
- The sample ID.
- The quarantine ID.
- The quarantine method.
- The disposition.

A sample can have memberships in more than one quarantine. This supports
overlapping methods without an arbitrary method priority.

### `LocationQuarantineResolution`

A resolution is immutable. It contains:

- A stable resolution ID.
- The quarantine ID.
- A positive revision.
- The Keep or Ignore decision.
- The resolving device ID.
- The resolution timestamp.

## SwiftData schema

Add these generation-scoped models to the live schema:

- `SDLocationQuarantine`
- `SDLocationQuarantineMembership`
- `SDLocationQuarantineResolution`
- `SDFlightQuarantineDetails`

Add an optional `isQuarantined` scalar to `SDLocationSample`.

All SwiftData fields and relationships remain optional for CloudKit. The
models do not use `@Attribute(.unique)` or `#Unique`.

Each relationship has one explicit inverse declaration. Each relationship
also has an explicit delete rule. Generation cleanup removes records
explicitly and does not depend on a cascade.

SwiftData model objects never cross an actor boundary. Store APIs return
Sendable value types and typed IDs.

### `SDLocationQuarantine`

The model stores the common quarantine fields. It also has optional
relationships to memberships, resolutions, and method-specific details.

The model stores the method as a stable string discriminator. It does not
store an associated-value enum.

### `SDLocationQuarantineMembership`

The model is an explicit join record. It stores scalar sample and quarantine
IDs in addition to optional relationships.

The scalar IDs preserve identity while related CloudKit records are absent.
The disposition uses a stable string discriminator.

### `SDLocationQuarantineResolution`

The model stores immutable resolution facts. The store accepts an identical
retry and rejects conflicting contents for the same resolution ID.

CloudKit does not supply a uniqueness constraint. The value layer groups
duplicate rows by ID and reports an immutable conflict.

### `SDFlightQuarantineDetails`

The flight details model stores only flight facts:

- The quarantine ID.
- The peak inferred speed in kilometers per hour.
- The number of confirmed flyover points.
- The speed threshold used by the detector.
- The minimum leg duration used by the detector.

A future method adds its own detail model. It does not add unrelated fields to
`SDLocationQuarantine`.

## Visibility contract

`SDLocationSample.isQuarantined` is the authoritative visibility gate. A nil
value means visible for compatibility with existing rows.

The store sets the value to true when any membership has one of these
dispositions:

- `candidate`
- `pending`
- `ignored`

The store sets the value to false when no blocking membership remains.

The store recalculates this value inside the same local transaction that
changes memberships. A remote-change reconciler repeats the calculation after
each CloudKit import.

A relationship alone is not a safe visibility gate. CloudKit can deliver the
sample and its membership in different import batches.

Each detector must claim a new sample during its initial ingest transaction.
This rule makes the new sample arrive with `isQuarantined` already true.

A future method that quarantines an old visible sample needs a separate
two-phase visibility protocol. That protocol is outside the first version.

### Visible sample reads

Normal history APIs return samples where `isQuarantined` is not true. These
consumers use the normal APIs:

- Reports and day aggregation.
- Widgets.
- Forecasts.
- Region attribution.
- Ordinary location history.
- Data-issue detectors, except for method-specific provenance checks.

### Complete sample reads

Backup, quarantine review, integrity checks, and classification recovery use
complete reads. These reads include hidden samples and all memberships.

The store API must use distinct names for visible reads and complete reads.
Callers must not select behavior through a Boolean parameter.

## Quarantine-method architecture

Add a `LocationQuarantineEngine` in WhereCore. The engine owns a compile-time
registry of method detectors.

Each detector conforms to an internal `LocationQuarantineDetecting` protocol.
The protocol exposes:

- The method discriminator.
- The recent-sample requirements.
- An evaluation operation.
- Method-specific detail mutations.

The evaluation input contains value types only:

- The new stamped automatic sample.
- Recent samples from the same recording device.
- Active candidates for that device and method.
- Existing memberships for the applicable samples.
- The current data-generation ID.

The evaluation result contains store mutations. A result can:

- Create a candidate.
- Add or update memberships.
- Confirm a quarantine.
- Close a quarantine.
- Release a candidate.
- Update method details.
- Produce an alert event after confirmation.

The detector does not write SwiftData. The engine applies all detector results
inside the current store transaction.

All registered methods can evaluate the same incoming sample. The engine does
not use a first-wins rule.

After all method results apply, the engine derives `isQuarantined` from every
membership for each changed sample.

## Flight quarantine method

`FlightQuarantineDetector` is the first registered method. It uses only public
Core Location sample coordinates, timestamps, accuracy, source, and visit
events.

Factor the common motion rules out of `FlightDayDetector`. The streaming and
post-hoc detectors use the same helper.

The rules are:

- A flight leg has an inferred speed of at least 300 km/h.
- A flight leg lasts at least 60 seconds.
- Fixes less than one second apart form one reading.
- The coalescing rule keeps the more accurate fix.
- A flyover point has a flight leg on both sides.
- Two consecutive flyover points confirm a flight.

The two-point rule rejects one teleport outlier. The duration rule rejects a
short interval that produces an unrealistic inferred speed.

### Streaming state

The first qualifying high-speed leg creates a candidate quarantine. The new
sample gets a `candidate` membership and becomes hidden.

The detector confirms the quarantine after two consecutive flyover points. It
changes the confirmed flyover memberships to `pending` and records flight
details.

If the sequence breaks before confirmation, the detector changes the candidate
memberships to `released`. The samples become visible again.

During a confirmed flight, interior flyover points remain pending. Origin,
landing, visit, and dwell samples remain visible.

A non-flight leg or compatible visit closes the active flight. The confirmed
flyover samples remain pending until the user resolves the quarantine.

An unconfirmed candidate releases after 24 hours without more evidence. This
rule prevents an abandoned device from hiding an endpoint indefinitely.

A confirmed quarantine never expires automatically.

### Historical safety net

Keep `FlightDayDetector` for historical data and streaming-detector misses.

The detector ignores samples with an accepted flight membership. A user-kept
flight must not immediately produce another flight issue.

The detector can still report a separate, unaccepted flight pattern on the
same day.

## Ingestion flow

`LocationIngestor` stamps the recording device before quarantine evaluation.
Only automatic GPS samples enter the quarantine engine.

Manual and evidence-implied samples bypass the quarantine engine.

For each automatic sample, the ingestor does this work:

1. Make sure that the recording authority and generation are current.
2. Read the classification context for the recording device.
3. Evaluate all registered quarantine methods.
4. Apply the sample, quarantine, membership, and detail mutations in one
   store transaction.
5. Recalculate visibility for each changed sample.
6. Commit the transaction.
7. Reconcile reports, badges, widgets, and notifications after the commit.

The automatic foreground capture follows the same flow. An audit-only current
location request does not persist or classify its result.

### Persistence errors and the outbox

The existing location outbox remains the durability boundary for a failed
store write. It does not become the quarantine source of truth.

An outbox entry stores the raw automatic observation and its generation. It
does not store a classification result.

The ingestor drains raw observations in timestamp order. Each observation
enters the quarantine engine again.

The store deduplicates stable sample IDs. A committed sample that remains in
the outbox cannot advance a detector twice.

If a quarantine transaction fails, the sample does not enter visible history.
The ingestor keeps the raw sample in the outbox and surfaces the error.

## Resolution and convergence

Keep and Ignore resolve one quarantine. They do not directly resolve other
quarantines that contain the same sample.

### Keep

Keep appends an immutable resolution. The reconciler changes the applicable
memberships to `accepted`.

The relationship and accepted provenance remain. The sample becomes visible
only when no other blocking membership exists.

### Ignore

Ignore appends an immutable resolution. The reconciler changes the applicable
memberships to `ignored`.

The samples and memberships remain in the store. They remain absent from
visible history and backups preserve them.

### Canonical decision

The first canonical resolution wins.

The first local resolution uses revision 1. A new resolution uses one more
than the highest observed revision.

The canonical resolver selects the lowest revision. If two concurrent
resolutions have the same revision, the lower UUID byte order wins.

The resolver does not use device clocks to select a winner.

A stale UI or notification action becomes a no-op after a canonical resolution
exists.

### Remote reconciliation

The quarantine reconciler runs after each remote store import. It does this
work:

1. Resolve duplicate immutable records by typed ID.
2. Select the canonical resolution for each quarantine.
3. Apply the canonical membership dispositions.
4. Recalculate sample visibility across all memberships.
5. Refresh pending-review counts and visible projections.

If a late concurrent resolution changes the canonical winner, the reconciler
reapplies that decision. Retained memberships make this reversal possible.

## Service interfaces

Expose a focused coordinator as `WhereServices.quarantines`.

The public service supports:

- Reading all pending quarantine summaries.
- Reading one quarantine, its samples, and its method details.
- Observing quarantine changes.
- Keeping a quarantine.
- Ignoring a quarantine.
- Reading the pending-review count.
- Reconciling resolutions after a remote import.

The UI does not access `WhereStore`, SwiftData, or `LocationIngestor` directly.

The existing `WhereStore` protocol gains explicit operations for:

- Classification context reads.
- Transactional quarantine mutations.
- Visible sample reads.
- Complete sample reads.
- Quarantine, membership, detail, and resolution reads.
- Immutable resolution insertion.

Core APIs do not use default parameters for quarantine behavior.

## Notifications and preferences

The first method adds **Flight Alerts** under Alerts settings. The preference
defaults to on.

The preference controls only the immediate flight notification. Detection,
sync, Resolve presentation, and quarantine visibility do not depend on it.

Launch and background detection only inspect notification authorization. They
do not request permission.

If the user turns Flight Alerts on, Where can request notification permission.
If the user denied permission, Settings shows the system-settings action.

The generic notification pipeline uses one actionable category. Each method
provides its title, body, icon context, and Ignore label.

The flight notification actions are:

- **Keep Locations**
- **Ignore In-Flight Locations**

The notification payload contains the quarantine ID and method discriminator.
The request identifier is stable for that quarantine.

Only the detecting device sends the immediate notification. Every device can
show and resolve the synced review.

Flights detected while alerts are disabled or unavailable do not send a later
notification. The pending review still appears in Resolve.

### Notification response handoff

Extend the notification-center delegate as a platform handoff. It must not
create a store or service stack.

The handoff queues a response that arrives before `WhereSession` exists. The
composition root installs the current session handler after session creation.

Keep and Ignore actions call `WhereServices.quarantines`. A default tap opens
the matching review.

Reset, generation replacement, and resolution remove owned pending and
delivered notifications.

## Resolve user interface

Add a **Location Reviews** section above ordinary data issues. This name does
not restrict the section to flights.

The section shows unresolved quarantines for all years. It does not depend on
the selected report year.

Use a common row and detail-screen shell. The method presentation supplies:

- The title.
- The symbol.
- The summary.
- The detail explanation.
- Method metrics.
- The Keep and Ignore labels.

The flight row shows the date range, time range, detecting device, held-sample
count, and peak inferred speed.

The flight detail explains the inferred-speed rule. It also explains that
Where kept the samples out of history.

The detail screen offers Keep and Ignore. The in-app Ignore action requires a
confirmation dialog.

The default notification tap selects Locations, opens Resolve, and navigates
to the matching detail screen.

The UI keeps the last good quarantine list after a read error. The UI shows an
honest error state for a failed decision.

### Counts and badges

Add these scene-model values:

- `pendingQuarantineCount`
- `resolutionItemCount`

`resolutionItemCount` equals the ordinary issue count plus the pending
quarantine count. The Resolve toolbar uses this combined count.

Issue Alerts continues to control the daily Resolve reminder and app-icon
badge. That count includes pending quarantines.

Flight Alerts controls only the immediate flight notification.

### Accessibility and localization

All new user-facing text uses generated localization symbols.

Rows and actions have explicit accessibility labels, values, hints, and stable
identifiers. The design does not use color as the only quarantine signal.

The layout supports accessibility Dynamic Type. A crowded metrics row must
restack instead of truncating values.

Previews and snapshots use production-shaped in-memory fixtures. They cover
pending, accepted, ignored, loading, and error states where those states are
visible.

## Backup format 6

Bump `BackupArchive.currentFormatVersion` to 6.

The archive contains:

- All location samples, including hidden samples.
- Generic quarantine records.
- Membership records.
- Immutable resolution records.
- Flight detail records.
- The existing collections and evidence assets.

Before import, validate these references:

- Each membership references an archived sample.
- Each membership references an archived quarantine.
- Each resolution references an archived quarantine.
- Each method-detail record references a quarantine with the same method.

The import transaction inserts scalar IDs and reconstructs optional SwiftData
relationships.

A merge import deduplicates immutable IDs and preserves the canonical
resolution rules. A replacement import rotates the generation before it
restores the archive.

Update `upgrade-backup.rb` to add empty quarantine collections to format 5 and
older archives. The upgrader does not change existing samples.

Update the backup integrity and WhereCore load tests for format 6.

## Reset and lifecycle behavior

Generation rotation makes old quarantine rows inactive. Normal reads only use
the active generation.

Explicit generation cleanup includes quarantines, memberships, resolutions,
and method-detail rows.

A replacement import restores only quarantine data from the new archive. A
rolled-back import preserves the previous generation and its quarantine data.

Device removal does not erase existing quarantines from that device. Another
device can resolve them.

Turning automatic recording off stops new observations. Existing confirmed
reviews remain available.

## Failure handling and logging

Do not silently convert a quarantine read error into an empty review list.
Preserve the last good value and log the error.

Do not persist a suspect sample as visible after a quarantine transaction
fails. Put the raw observation in the existing outbox.

If a remote import has a membership but lacks its parent, keep the sample
hidden. Reconcile again after the parent arrives.

If an immutable record ID has conflicting contents, log a fault and use the
existing deterministic conflict rule.

Add structured log events for:

- Candidate creation and release.
- Quarantine confirmation and closure.
- Notification scheduling and suppression.
- Keep and Ignore decisions.
- Canonical-resolution conflicts.
- Remote reconciliation.
- Visibility repair.
- Corrupt or incomplete records.

Logs must not include raw coordinates.

## Implementation sequence

1. Add the generic domain values and visible-sample contract.
2. Add the SwiftData models, store operations, and remote reconciliation.
3. Add backup format 6 and the backup upgrader.
4. Add the generic quarantine engine and raw-outbox replay path.
5. Factor the shared flight-motion rules.
6. Add `FlightQuarantineDetector` and its detail model.
7. Add the generic quarantine coordinator to `WhereServices`.
8. Add the preference and notification handoff.
9. Add Resolve presentation, routing, localization, previews, and snapshots.
10. Update WhereCore and WhereUI module documentation.

Each step must keep the store readable and the visible-sample contract intact.

## Test plan

### Generic domain and engine

- Test each disposition and its visibility effect.
- Test multiple quarantine methods on one sample.
- Test Keep for one method while another method remains blocking.
- Test Ignore retention and accepted provenance.
- Test candidate release and confirmed-review retention.
- Test deterministic resolution revision and UUID tie-breaking.
- Test stale and duplicate decisions.

### Flight method

- Test speeds below, at, and above 300 km/h.
- Test leg durations below, at, and above 60 seconds.
- Test a short teleport and an out-and-back outlier.
- Test two consecutive flyover points.
- Test near-simultaneous duplicate fixes and accuracy selection.
- Test origins, landings, visits, dwells, and layovers.
- Test overnight and multi-day flights.
- Test out-of-order callbacks.
- Test more than one flight before a user decision.
- Test the 24-hour release for an unconfirmed candidate.
- Test that accepted flights do not produce another flight issue.

### Ingestion and persistence

- Test one transactional write for the sample and quarantine mutations.
- Test a generation change during classification.
- Test outbox replay in timestamp order.
- Test a committed sample that remains in the outbox.
- Test process relaunch with an active candidate.
- Test process relaunch with a confirmed flight.
- Test a quarantine write error without a visible sample leak.

### SwiftData and CloudKit ordering

- Test a sample before its quarantine parent.
- Test a parent before its sample.
- Test a membership before either related record.
- Test a resolution before its quarantine.
- Test stale `isQuarantined` repair after a remote import.
- Test duplicate immutable rows and conflicting contents.
- Test several memberships with mixed dispositions.

### Reports and projections

- Test that candidate, pending, and ignored samples do not enter reports.
- Test that accepted and released samples enter reports.
- Test widgets, forecasts, attribution, and day aggregation.
- Test ordinary issue counts and quarantine counts together.
- Test projection rebuild after Keep, Ignore, and remote reconciliation.

### Notifications and settings

- Test that Flight Alerts defaults to on.
- Test that launch does not request notification permission.
- Test that an explicit toggle can request permission.
- Test one notification from the detecting device.
- Test no duplicate alert on another device.
- Test disabled, denied, and unavailable notification states.
- Test notification payloads and stable identifiers.
- Test actions that arrive before session installation.
- Test stale actions and notification removal.

### Resolve user interface

- Test pending-review loading and last-good-value retention.
- Test the combined Resolve count.
- Test default-tap routing to the correct detail.
- Test Keep and Ignore progress and errors.
- Test the Ignore confirmation dialog.
- Add snapshots for the generic list and flight detail.
- Cover light, dark, accessibility text, and relevant localization layouts.

### Backup and lifecycle

- Test a format-6 export and import round trip.
- Test hidden and accepted sample preservation.
- Test malformed membership references.
- Test merge deduplication and canonical resolutions.
- Test replacement generation behavior.
- Test the format-5 to format-6 upgrader.
- Test reset, import rollback, device removal, and recording Off behavior.

## Validation commands

Use the repository scripts for validation:

```sh
./swiftformat --lint
./sf-symbols --lint
./xcstrings --lint
./test --all
./test --snapshots
```

The default `./test` path must also run the backup-upgrader regression.

## Acceptance criteria

- A blocking sample never appears in visible history.
- A newly synced blocking sample arrives with a safe visibility value.
- A confirmed review appears on every device after CloudKit sync.
- Keep makes samples visible only after all blocking memberships resolve.
- Ignore retains samples and keeps them hidden.
- Accepted memberships preserve method provenance.
- Concurrent offline decisions converge to one deterministic result.
- A kept flight does not create another flight issue.
- The detecting device sends no more than one immediate notification.
- Detection does not request notification permission.
- Format-6 backup preserves all quarantine data.
- Existing stores and upgraded backups have no quarantines by default.
- The first version uses only public APIs.
