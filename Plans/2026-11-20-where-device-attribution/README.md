# Device names and attribution in Where

If Travel Phone records a location and Home iPad corrects it, the saved point should identify Travel Phone and the correction should identify Home iPad. Both roles should survive a rename, removal or restore.

## Planning checkpoint

- **Request.** On November 20, 2026 the owner asked for a plan covering device names, model-based fallback, and the origin of actions and locations. Their existing history comes from one phone. They selected the offline upgrader for old data.
- **Operation.** On November 27 the owner approved execution of the full series. Plan PR #547 at `41b1b116b` has no review comments or threads. Main is `a6b213ebe`. The owner selected synthetic archives for this run and asked to leave the live two-device CloudKit test pending.
- **Stage.** [01](01-location-provenance.md) shipped for review in [PR #573](https://github.com/kyleve/Stuff/pull/573) at `be7c927c7`. Executing [02](02-device-names.md) on `codex/where-device-names`. The identity worker owns setup, local identity and Settings. The events worker owns synced metadata, registration and resolution. The backup worker owns offline conversion and its verification driver. The primary agent owns model labels, archive admission and compatibility, end-to-end checks, review and publication.
- **Resume.** Verify registration on a generic profile, an upgraded synthetic archive, and setup snapshots. Publish 02 and use its results to refine and execute [03](03-action-attribution.md). [STU-337](https://linear.app/kve/issue/STU-337)

## User stories

| ID | Owner's goal |
| --- | --- |
| US-01 | Recognize each device during setup, in Settings and when reviewing older activity. |
| US-02 | See which installation captured a location, made a manual entry or changed saved data, even when reviewing it from another device. |
| US-03 | Carry the history from my existing phone into the new format and preserve attribution on later exports and restores. |

## Requirements

| ID | Observable result | Stories | Plans |
| --- | --- | --- | --- |
| R-01 | Setup offers a familiar model name that the owner may accept or edit. Unknown models display the hardware identifier. Settings can rename the device or clear its nickname to return to the fallback. | US-01 | [02](02-device-names.md) |
| R-02 | Devices with identical names or models remain distinct by installation ID. Saved history resolves the latest saved nickname or that device's model fallback, including after removal. | US-01, US-02 | [02](02-device-names.md) |
| R-03 | Every saved GPS observation identifies its capturing installation. Retrying, syncing, renaming and viewing preserve that ID. | US-02 | [01](01-location-provenance.md) |
| R-04 | Each GPS correction and reset identifies the installation that made the change. Editing preserves the raw observation and its capture ID. An explicit history erase can delete the observation. | US-02 | [01](01-location-provenance.md) |
| R-05 | Each edit, event or location Where already retains identifies the installation responsible, including manual entries and evidence. A replacement keeps the author of the winning edit with that edit. Clearing a row keeps its existing deletion behavior. | US-02 | [03](03-action-attribution.md) |
| R-06 | Merge, Replace and the offline upgrade preserve known roles and record identities. The owner's single-phone archive can acquire missing origin IDs without inventing a sequence of past edits. | US-03 | [01](01-location-provenance.md), [02](02-device-names.md), [03](03-action-attribution.md) as each changes stored data |
| R-07 | Existing device labels use the shared name lookup. Stored and exported records expose recorder and author in their respective roles, including for actions with no UI. | US-01, US-02 | [02](02-device-names.md) supplies names. [03](03-action-attribution.md) verifies the roles. |

## Scope boundaries

| ID | Boundary | Reason |
| --- | --- | --- |
| X-01 | Keep legacy decoding and backfill in the offline upgrade tool. | The owner can export and upgrade their only phone's archive. |
| X-02 | Reuse the installation identity and existing local recording consent. Exclude serial numbers, new accounts, a hardware-based identity and remote changes to consent. | Two installations of the same model can record different actions. A replacement installation has its own identity. |
| X-03 | Keep the existing tables, detail views, retention and erasure rules. Exclude a new activity feed, a parallel audit table, tap analytics, extra check-ins and events for reads or computed results. | The requested audit concerns who recorded or changed the owner's data. A reader, projection or import must never impersonate a historical author. |

## Discovery and evidence

Discovery began at `1b04fdd2c`. The November 27 revision uses `a6b213ebe` for store admission and archive behavior. The migrated [STU-301](https://linear.app/kve/issue/STU-301) records earlier naming work as Done. The current setup flow still lacks a name field. [STU-221](https://linear.app/kve/issue/STU-221) separately tracks an entitlement for reading a system-assigned name. Neither issue covers attribution for actions.

| Workflow | Existing behavior and consequence |
| --- | --- |
| Start, return, or rejoin | The [installation sidecar](../../Where/WhereUI/Sources/Launch/InstallationRecordingContextStore.swift) freezes the installation ID, registration time, generic hardware family and recording choice outside backups. [Onboarding](../../Where/WhereUI/Sources/Onboarding/OnboardingFlowModel.swift) confirms the choice, may import a backup, then registers the installation. Opening setup or demo must remain free of real registration writes. After data-version admission, an installation can make edits with recording Off. |
| Name and rename | [DeviceRecordingController](../../Where/WhereCore/Sources/Devices/DeviceRecordingController.swift) already registers immutable profiles, attributes nickname changes and supplies historical names including removed profiles. [Settings](../../Where/WhereUI/Sources/Settings/DeviceSettingsRowModel.swift) has its own display rule. The phone currently supplies a family name such as “iPhone”. The logging module already reads the machine identifier, with a simulator caveat. [Apple's model documentation](https://developer.apple.com/documentation/uikit/uidevice/model) · [LogSession](../../Shared/Periscope/PeriscopeCore/Sources/Store/LogSession.swift) |
| Record, correct, retry | [LocationIngestor](../../Where/WhereCore/Sources/Location/LocationIngestor.swift) stamps live GPS and retries buffered observations. [LocationSample](../../Where/WhereCore/Sources/Location/LocationSample.swift) can still represent an unstamped fix. [SampleAttributionRevision](../../Where/WhereCore/Sources/DataResolution/SampleAttributionRevision.swift) records the sample, time and revised regions but has no editor ID. Device removal and flight grouping rely on capture identity. |
| Act on another device | A [manual-entry audit](../../Where/WhereCore/Sources/Journal/ManualEntryAudit.swift) records time, optional note and optional fix. A [day clear or issue restore](../../Where/WhereCore/Sources/Journal/DayJournal.swift) removes state. Under the agreed retention rule, a day clear can still remove the sole record of that entry. The [action inventory](03-action-attribution.md#coverage-inventory) covers the other writers. |
| Restore on B | The [v8 archive](../../Where/WhereCore/Sources/Backup/BackupArchive.swift) carries raw observations, correction revisions, device profiles and metadata. [Replace](../../Where/WhereCore/Sources/Backup/BackupCoordinator.swift) starts a new generation under B's authority. The old capture retains its own ID. V8 supports Canadian subdivision IDs and lacks the correction author, which the upgrader can supply for the owner’s single-phone history. An input containing only “iPhone” cannot reveal the old phone's specific model. |

## Execution order and planning horizon

| Order | Deliverable | Dependency |
| --- | --- | --- |
| 1 | [Identify the GPS recorder and correction author](01-location-provenance.md). Acceptance requires a two-device fixture to preserve both roles through persistence and backup. | Independent. The capture and correction IDs establish the roles used throughout the series. |
| 2 | [Name each installation](02-device-names.md). Setup, Settings and historical lookups use the same name rules. | Follows 01 so any changes to the metadata format extend its tested upgrader. |
| 3 | [Attribute existing actions](03-action-attribution.md). Extend the pattern to manual entries, evidence and other agreed changes. | Uses the proven origin/actor distinction from 01 and historical names from 02. |

The current horizon covers 01 and 02. Their diagrams and Swift sketches show the proposed boundaries. Refine 03 using the actual storage and resolver APIs that 01 and 02 deliver. Its coverage and retention rules are settled.

## Shared decisions

- The owner chose an editable model-based name, a familiar label for known hardware and the raw identifier for unknown hardware. Existing records and revisions own their author. Existing places that display devices use the same names. Inspection of stored and exported records covers new author fields.
- Use `RecordingDeviceID` throughout. The field identifies the role of recorder, editor or target. Store IDs with data. Resolve names on read through the existing device registry.
- Use the [versioning and rollout rules](#versioning-and-rollout) for each independently shipped change. Keep the existing removal, generation and store-notification contracts. [WhereCore contracts](../../Where/WhereCore/AGENTS.md)
- Keep the hardware identifier with the global installation profile through a field in the existing device metadata table. The immutable profile can then match a profile already synced from the old phone. Nickname edits keep their existing generation boundaries.
- Use the owner's single-phone assumption only to fill absent information in an offline archive. The importing installation's identity and GPS consent belong to the destination. Existing IDs, timestamps, tombstones, notes and evidence bytes travel with their original records.

## Versioning and rollout

| Boundary | On main at `a6b213ebe` | What each implementation changes |
| --- | --- | --- |
| Opening shared history | The last entry in `DataModelVersion.changes` sets `current`. Entry 2 explains why visits to Canadian provinces and territories require an update. Baseline is 1. | For each incompatible release, append the next version with a user-facing reason from the WhereCore string catalog. Preserve prior entries and their reasons. [Version history](../../Where/WhereCore/Sources/Compatibility/DataModelVersion.swift) · [String catalog](../../Where/WhereCore/Sources/Resources/Localizable.xcstrings) |
| Importing a ZIP | `BackupArchive.currentFormatVersion` and the Ruby upgrader target 8. The importer checks the envelope before decoding the payload. | Advance the archive format when an older app cannot restore the exported data losslessly. Extend the offline conversion in the same change, including for ZIPs moved between accounts. [Archive history](../../Where/WhereCore/BACKUP_FORMAT.md) · [Upgrader](../../Where/Tools/upgrade-backup.rb) |

With this base and separate releases, 01 takes shared data from **2 to 3** and archives from **8 to 9**. The next release for 02 would use **4 and 10**. Read both histories again at implementation time so another release can take the next number.

In CloudKit, the eligible recording device publishes the higher version and all bundled translations of its reason in one conditional save. An older reader that observes the new version blocks access and caches the version and reason in its receipt. The lockout uses the reader’s preferred language, falls back to English, and uses the standard update message if the reason is unavailable. A local-only installation verifies the build’s version against its durable floor. [Compatibility contract](../../Where/WhereCore/README.md#data-compatibility)

Before distributing a cloud-enabled recorder build, exercise its new mirrored fields in CloudKit Development and verify that the control record carries the version and reason. Confirm the fields exist in Production, deploying any additions before rollout. Bring participating installations onto a gate-aware build before the recorder advances their account. A disconnected reader can continue under its last verified version until it observes the higher floor. [CloudKit rollout and device validation](../../Where/Where/README.md#cloudkit-rollout-and-device-validation)

## Questions and resolutions

### Q-01

**Closed · R-01.** Asked and answered by the owner November 20. Show the model name at setup and let the owner accept or edit it. An empty nickname uses the displayed model. Incorporated in the [setup steps and tests](02-device-names.md#steps) for fresh installs, restore and rejoin.

### Q-02

**Closed · R-01/R-02.** Asked and answered by the owner November 20. Use a familiar label such as “iPhone 15 Pro” for a known identifier and the identifier itself for an unknown model. The [naming plan](02-device-names.md) covers known, unknown, duplicate and removed devices.

### Q-03

**Closed · R-05/R-07.** Asked and answered by the owner November 20. Record the author alongside each edit, event or location Where already keeps. The [action inventory](03-action-attribution.md#coverage-inventory) assigns those records and preserves existing deletion and conflict-resolution behavior. A unified audit table or a new history screen would exceed the requested scope.

### Q-04

**Closed · R-06 · resolved November 20.** Where should historical attribution be repaired? The owner specified an external upgrade for their one phone. The backup contract confirms strict current-format loading. Incorporated into R-06, X-01 and the upgrade acceptance criteria in [01](01-location-provenance.md). Known IDs survive and ambiguous archives require an explicit source identity.

## Plan review and handoff

Reviewed November 20, 2026 against `1b04fdd2c`. The review traced all seven requirements, compared the two ready plans with their write, restore and name-resolution paths, and checked the later outline against the owner’s retention decision.

- Same-ID profile changes would conflict with a generic profile already in CloudKit. Plan 02 preserves the profile and adds model information to existing metadata. Its restore test starts with that profile already present.
- A permanent capture-ID conflict could otherwise keep re-entering the retry queue. Plan 01 distinguishes this failure from a transient save error. Its year-clear case also checks that a retained reset identifies the editor even after the raw fix is deleted.
- November 27, 2026. Rechecked all three plans against merged main `a6b213ebe`. The November 20 version instructions are superseded. Each incompatible release now appends its own localized reason to the shared-data history. The archive upgrade covers v8 and both v7 paths, with a manual-only Ontario fixture to catch lost region IDs or invented device records. The live verification uses a CloudKit-enabled Development build.
- **Readiness.** 01 and 02 are ready in order. 03 is an outline awaiting their implementation evidence. All product questions are closed.
- **Validation on November 27.** Checked relative links and anchors, dependency order and referenced test suites against the merged tree. `./test` passed its architecture and host checks and selected zero affected iOS bundles. The backup upgrader passed 16 tests and 61 assertions. Runtime acceptance of the proposed changes, including the two-device CloudKit check, awaits implementation.

The owner approved implementation on November 27. [Planning PR #547](https://github.com/kyleve/Stuff/pull/547)
