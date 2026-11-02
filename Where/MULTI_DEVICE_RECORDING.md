# Multi-device recording

This document defines the replacement direction for exclusive recording authority.
It is the design foundation for a new stack based on `main` at `93062f7c`.
This first slice changes documentation only. History selection and conflict review remain unimplemented.
This document also owns the implementation plan for the replacement stack.

## Product contract

Each device can record with its own local consent.
Where retains the observations and their device provenance.
History selection determines which observations represent the user's region history for a period.
Selection never requires another device to stop recording.

A user can carry different devices during one day.
For example, they can carry a Pro Max in the morning, a Duo in the afternoon, and a Watch during a run.
Selection applies to bounded periods. A whole-day choice is a convenience over those periods.
The day remains a useful review unit, with the report's existing calendar and time-zone rules.

The first version automatically selects a device when the evidence is strong.
Each automatic decision exposes its reason and supports a manual override.
Ambiguous conflicts remain available for review.

## Region agreement and movement

Different coordinates in the same effective region do not create a region-history conflict.
Those observations remain distinct records with their original coordinates.
Region agreement does not justify joining different devices into one physical trajectory.

A region conflict requires competing evidence for the same period.
Different regions at different times can describe ordinary travel.
Comparing each device's whole-day region set is insufficient.
The resolver must account for observation times, gaps, accuracy, and existing region corrections.

Movement provides evidence about which device accompanied the user.
A coherent moving track can outweigh fresh, repeated stationary observations from another device.
A single distant point, GPS noise, or better accuracy alone does not establish that choice.
The number of devices does not establish the user's location either.
Two phones at home must not automatically outvote a Watch on the user's wrist.

Missing observations provide no stationary evidence.
A device without observations adds no competing track for that period.
Its last position must not silently extend across an unbounded gap.
The absence of another track also does not increase the quality of the available observations.

Movement remains an inference about the user.
For example, a moving phone can travel with someone else while the user stays home.
The user can correct that inference without losing either track.

## Required scenarios

| Evidence | Expected region-history behavior |
| --- | --- |
| Both phones report different coordinates within the same region | No device conflict. Preserve both sets of observations. |
| One phone travels across regions while another repeatedly reports from home | Automatically select the moving phone where the evidence is strong. Explain the selection. |
| A Watch travels while two phones remain at home | Assess the evidence without a device-count vote. |
| The user changes phones during the day | Permit different selected devices in different periods. |
| One device reports and another remains silent | Assess the available track. Do not infer a stationary track from silence. |
| Two devices travel in different regions during the same period | Request review unless independent evidence supports automatic selection. |
| A sparse track or inaccurate boundary point suggests movement | Preserve uncertainty. Do not classify it as strong movement evidence. |
| A Watch syncs after the phone's initial report | Reassess automatic selections and update affected outputs. Preserve explicit user choices. |
| The user changes a previous source choice | Rebuild effective history while retaining the raw observations. |

These scenarios define acceptance criteria. They are not claims of current test coverage.

## Data and decision boundaries

Raw observations remain the durable evidence.
Backups and diagnostic review retain their original coordinates, timestamps, accuracy, source, and installation identity.
Automatic selection does not erase observations or rewrite their device identity.
Existing explicit removal, reset, and deletion operations retain their separate contracts.

Automatic decisions are derived results.
Their evidence and policy version explain the result and permit reassessment after late sync or a policy change.
User choices are durable decisions with explicit period boundaries.
They take precedence over automatic selection and remain reversible.
Concurrent, overlapping user choices require a defined resolution policy before persistence ships.

Device selection applies to automatic GPS evidence.
It does not override manual entries, authoritative day overlays, or evidence-derived assertions.
It must compose explicitly with existing per-sample region corrections.
Legacy samples without a device identity remain available without an invented identity.

Every consumer must use the same effective history contract.
Reports, widgets, reminders, issue scans, and relevant App Intents must agree after local writes, remote imports, and user choices.
Raw track review remains available separately.
Flight and movement inference must preserve device boundaries.
An unresolved region conflict must remain visible to consumers, rather than silently becoming a confident combined history.

## What main already provides

The new stack starts from the existing implementation.
It does not require a wholesale import of the previous stack.

| Existing owner | Reuse boundary |
| --- | --- |
| [RecordingDeviceID](WhereCore/Sources/Devices/RecordingDeviceID.swift) and [LocationSample](WhereCore/Sources/Location/LocationSample.swift) | Installation identity and automatic-sample provenance already exist. |
| [DeviceRecordingController](WhereCore/Sources/Devices/DeviceRecordingController.swift) | Local consent and device lifecycle already operate without exclusive ownership. |
| [LocationIngestor](WhereCore/Sources/Location/LocationIngestor.swift) and [LocationOutbox](WhereCore/Sources/Location/LocationOutbox.swift) | Capture stamps provenance and retains accepted writes across persistence failures. |
| [LocationHistoryReader](WhereCore/Sources/Devices/LocationHistoryReader.swift) | The shared read boundary already applies device removals and region corrections. |
| [LocationHistoryReaderTests](WhereCore/Tests/LocationHistoryReaderTests.swift) | Existing guards preserve raw observations while applying corrections and removal cutoffs. |

The current reader has no device-selection policy or unresolved-conflict result.
It provides an integration boundary, not a completed multi-device resolver.
The existing correction guards do not prove the new acceptance scenarios.

## Previous stack reuse

The previous stack remains a reference at `14d71446e7afe8551da5b20ee8be0bd0dcc668e3` ([PR #457](https://github.com/kyleve/Stuff/pull/457)).
Each imported change requires a concrete need and focused validation in the new stack.

| Previous concern | Treatment in the replacement |
| --- | --- |
| Ownership grants, claims, approval fences, handoffs, and lost-owner recovery | Excluded from the new recording model. |
| Sample ownership IDs and exclusions tied to ownership periods | Excluded. Existing device provenance is the starting point. |
| Device identity and local consent | Reuse the implementation already on main. |
| Compatibility checks, transaction guards, and scope retirement | Assess separately when new stored decisions require older clients to stop. |
| Owner-only compatibility upgrades | Excluded. A compatibility policy cannot depend on an exclusive recording owner. |
| Snapshot references for authority and handoff screens | Excluded. New presentation receives its own fixtures. |

Compatibility remains a separate data-contract concern.
Older clients must not silently ignore selection decisions and publish conflicting history.
The version policy and rollout gate must precede activation of any incompatible stored behavior.

## Implementation plan

The stack starts with this design slice. The following slices establish and activate the replacement model.
Each slice receives its own tests and PR.

### 1. Device-evidence assessment

Define bounded periods, accuracy-aware movement evidence, stationary evidence, and uncertainty around sparse observations.
Use the required scenarios as executable fixtures.
Preserve same-region agreement and separate device trajectories.
The assessment remains independent of production filtering in this slice.

### 2. Durable user choices and compatibility

Extend the value-based store and backup contracts with bounded user decisions and explicit reversal.
Define concurrent-choice behavior and precedence with sample corrections and manual overlays.
Resolve older-client compatibility independently of recording ownership before activation.

### 3. Shared history selection

Extend `LocationHistoryReader` with effective selections and explicit unresolved conflicts.
Cover reports, issue scans, widgets, reminders, and relevant App Intents.
Exercise local writes, delayed sync, user overrides, reset, and device removal.
Preserve raw review, backups, manual assertions, and device boundaries in trajectory inference.
Define unresolved-conflict presentation before changing totals.

### 4. Review experience and activation

Expose automatic-selection reasons and manual overrides through the existing resolution flow.
Support different devices during one day and a whole-day convenience action.
Use representative phone and Watch scenarios in previews and snapshots.
Activate selection only with durable choices, consumer integration, compatibility behavior, and tested review surfaces.
The Watch scenarios establish the data contract. A shipping Watch app remains separate work.

## Open implementation decisions

The following boundaries require explicit decisions in the relevant slices:

- Interval segmentation, boundary inclusivity, and context outside a queried day.
- Accuracy-aware movement and stationary thresholds, evidence freshness, and sparse-track behavior.
- Interaction between device choices, per-sample corrections, and manual day overlays.
- Identity, revision ordering, concurrent choices, and reversal of a user decision.
- Treatment of unresolved conflicts in totals, exports, widgets, and reminders.
- Backup, reset, device removal, and compatibility behavior for stored choices.

Thresholds require named units and scenario tests before they affect history.
The automatic policy must produce the same result for the same evidence, regardless of input or sync order.
The first executable slice can establish that policy without changing capture or report behavior.
Activation follows durable choices, consistent consumer integration, and a usable review path.
