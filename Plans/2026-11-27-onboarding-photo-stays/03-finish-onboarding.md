# 03 — Save the reviewed year and finish onboarding

- Status: outline
- Depends on: [02 — Review stays](02-review-stays.md)
- Shared context: [Overview](README.md)

## Intended outcome

Fresh, interactive setup offers the photo scan, stay review and region picker in order. Explain that Where looks for likely device captures by excluding identifiable Shared Album photos and checking how soon each photo entered the library. Invite the user to remove visits from received or synced photos that pass. Someone can grant limited Photos access, correct a trip, pick different primary regions from the suggestions, turn automatic recording off and still finish with the reviewed history. Reopening Where shows the same accepted points, stay dates and primary choices.

| Story | Requirement | Outcome |
| --- | --- | --- |
| [US-01](README.md#user-stories) | [R-01, R-09](README.md#requirements) | The fresh setup offers scan, skip, progress and retry. Limited access, denial, cancellation and empty results all have an accessible route onward. |
| [US-03](README.md#user-stories) | [R-06](README.md#requirements) | The picker presents the ranking from 02. Only the user's selections, pick order and appearances become the configured primary regions. |
| [US-02, US-03](README.md#user-stories) | [R-07](README.md#requirements) | Approved photo points retain their origin. The calendar and year report retain corrected days, including visits to places the user did not choose as primary. |
| [US-03](README.md#user-stories) | [R-08, R-09](README.md#requirements) | A failed or interrupted Finish can recover safely. Skipping Photos and the existing restore, demo and recording-choice-only routes still work. |

## Known design

The regular onboarding flow owns the transient review until the user chooses Finish. Keep the existing compatibility admission, installation recording choice and single scope resolution. The launch contract permits an early store opening specifically for recording-device discovery. Photo scanning and editing need no store, session or recording authority. Headless launch remains parked at the gate. The existing finish method logs a region-write failure and can proceed. The new reviewed-history path must surface save errors and hold the gate until the commit succeeds. [Launch contract](../../Where/Guidance/launch.md) · [Onboarding flow](../../Where/WhereUI/Sources/Onboarding/OnboardingFlowModel.swift)

```mermaid
flowchart TD
    A["Approved draft and explicit picks (02)"] --> B["Finish in admitted real scope"]
    B --> C["Proposed guarded Core transaction"]
    C -->|changed evidence| D["Review affected days or primary choices"]
    D --> B
    C -->|committed| E["Reconcile day data and acknowledge onboarding"]
    E --> F["Existing launch handoff"]
```

```swift
// Proposed Core operation reached through WhereServices; storage types await Q-05.
let outcome = try await store.perform(expectedDataGenerationID: reviewedGeneration) {
    // Read a single snapshot of existing assertions, accepted points and primary rows.
    // Return affected items for review if applying the draft would change prior intent.
    // Write approved photo facts, reviewed day attribution, ordered picks and a receipt.
}
// After commit, reconcile day data and finish the installation's onboarding handoff.
```

**History and selection.** Persist the approved capture time, coordinate, available accuracy and explicit photo origin. Keep photo facts separate from passive fixes, device authority and flight inference. Account for unavailable accuracy without inventing a measurement. Store accepted calendar days and corrections so moving a boundary, rejecting an observation or deselecting a primary cannot add phantom days or erase a non-primary stay. A confirmed gap contributes reviewed days without synthetic map points. Reassess maps, widgets and reports through the effective history reader. Today that reader attributes points against the tracked set and applies sample revisions only to live GPS. A new source tag alone cannot preserve the reviewed result. [Sample sources](../../Where/WhereCore/Sources/Location/LocationSample.swift) · [History projection](../../Where/WhereCore/Sources/Devices/LocationHistoryReader.swift) · [Ranking](../../Where/WhereCore/Sources/Days/Region+Ordering.swift) · [Picker](../../Where/WhereUI/Sources/Regions/PrimaryRegionSelectionModel.swift)

**Conflict and failure.** On Finish, capture the admitted store's generation and inspect affected days and primary rows. Surface overlaps that would change existing assertions or explicitly saved picks, with choices to keep existing data or approve the specific change. Revalidate those decisions in the transaction's `readSnapshot`. A concurrent edit returns a fresh review. Account changes and Reset or Replace invalidate the attempt. Preserve unrelated regions, prior GPS corrections, and manual-entry audit records, including all days of an earlier range edit. Record when the user approved a correction or gap. Photo coordinates describe capture time and must stay out of the audit field for the device's location when editing. Blindly looping over `setManualDay` can replace an additive row or change an authoritative row's regions and audit. Keep the confirmed selections and the history in one transaction. Reconcile using existing day-write fan-out after commit. [Store contract](../../Where/WhereCore/Sources/Persistence/WhereStore.swift) · [Manual writes](../../Where/WhereCore/Sources/Persistence/SwiftDataStore.swift) · [DayJournal](../../Where/WhereCore/Sources/Journal/DayJournal.swift)

**Interrupted Finish.** Bind the commit's identity to this installation, admitted domain and generation. A retry or relaunch after commit but before the onboarding marker must recognize the same successful operation, finish pending reconciliation and acknowledgment, and avoid duplicate points or repeated assertions. Never replay an uncommitted draft into a different account or generation. Backup restore has its own recovery sequence. Preserve that independent ownership. [Launch recovery contracts](../../Where/WhereUI/Sources/Launch/AGENTS.md) · [Backup contracts](../../Where/WhereCore/Sources/Backup/AGENTS.md)

**Compatibility.** Baselines at planning time are backup format 8 and data model version 2. Specify the next strict backup format, external v8 upgrade and merge/replace round trips for every new durable history field. Preserve older GPS, manual entries and audits. Document incompatible data semantics in the next model-version entry with a localized reason and retain existing admission and publication rules. Verify an admitted viewer with recording off can finish. [Archive](../../Where/WhereCore/Sources/Backup/BackupArchive.swift) · [External upgrader](../../Where/Tools/upgrade-backup.rb) · [Version history](../../Where/WhereCore/Sources/Compatibility/DataModelVersion.swift) · [Publication rules](../../Where/WhereCore/README.md#data-compatibility)

## Boundaries

[X-01–X-03](README.md#scope-boundaries) apply. Process metadata on device. Keep image bytes, library identifiers and unapproved points out of the saved history. Approved history follows Where's ordinary storage and backup settings. This route is for fresh interactive setup. Demo, restore, Flyover, recording-choice-only setup and extensions do not request Photos access. Travel forecasting and continuous library monitoring are outside this series.

## Refinement trigger and outcome evidence

After 02 demonstrates explicit gap confirmation and corrected rankings, use its approved-draft fixture to resolve [Q-05](README.md#questions-and-resolutions). Choose the persisted representation of reviewed attribution, idempotent point identity, transaction receipt and launch acknowledgment. Trace one accepted observation, one relabeled stay and one approved gap through a cold read, backup and retry before marking this plan ready.

- In Core, prove the calendar totals and visible photo points agree with the draft after reopen, a later primary edit, backup merge, backup replace and external upgrade. Exercise two regions on one day, a removed assignment, an existing authoritative day, a concurrent change, save failure and duplicate Finish.
- Include a photo just after local midnight on January 1. Approve the stay, change to a time zone where that instant falls on December 31, and reopen both year reports. The original point keeps its capture instant. The approved stay keeps its reviewed calendar day, including in the presence of year-bounded fetches. [Day identity](../../Where/WhereCore/Sources/Days/AGENTS.md)
- In launch tests, stop immediately after commit and before the onboarding preference. Relaunch with Photos access revoked. The app can finish once from the committed result. Verify compatibility retirement and reset cannot revive that attempt. Exercise skip, denial, restore, demo, headless promotion and the second-device recording choice. [WhereLaunchTests](../../Where/WhereUI/Tests/WhereLaunchTests.swift) · [BackupCoordinatorTests](../../Where/WhereCore/Tests/BackupCoordinatorTests.swift)
- On a device, grant limited access to known photos covering a travel day, several photos in one region, an image without GPS and a short gap. Repeat with full access to a test library containing a known Shared Album asset and a main-library image saved more than five minutes after capture. Verify that neither supplies a point or changes a stay or region count. Exercise cancellation during a larger scan and restart it. Review and edit a stay, explicitly confirm or decline the gap, leave a visited region unselected, then finish with recording off. Verify the photo provenance, points and expected day totals after relaunch. Exercise the manual picker after denial and the accessible labels for permission, correction, suggestions and retry.

## Decisions and resume point

The November 27 product choices [Q-01–Q-04](README.md#questions-and-resolutions) govern gap confirmation, photo retention, active region selection and the seven-missing-day suggestion limit. [Q-05](README.md#questions-and-resolutions) affects this plan's storage and recovery design. Refine it with the reviewed draft and a failure-injection fixture after 02 completes. Implementation has not started.
