# Where backup format v11

`BackupArchive` is the authoritative manifest schema. A ZIP contains its JSON
manifest and the referenced evidence assets. The production `BackupService`
decoder accepts the current version only; upgrade older archives with
[`Where/Tools/upgrade-backup.rb`](../Tools/upgrade-backup.rb).

## Version history

Version numbers were reused during development. The commit identifies the exact historical shape.
Current imports require the current schema, including its required collections.

| Version | Change | Source |
| --- | --- | --- |
| 1, original | ZIP with `manifest.json`, samples, evidence, manual days, and an asset index. Later additive revisions included dismissals and tracked regions. | [Backup export/import](https://github.com/kyleve/Stuff/commit/6aa120db4b4e966575f0271e9275bd237bd945d8) |
| 2, first use | Replaced manual-day `date` instants with `CalendarDay` identities. The temporary reader still accepted version 1. | [CalendarDay](https://github.com/kyleve/Stuff/commit/7bbaafca) |
| 1, schema reset | Removed legacy decode fallbacks and required current collections. Dismissal identities became `store://` URLs. | [Schema cleanup](https://github.com/kyleve/Stuff/commit/4b67c45980b668b0e9de9fac547b4662522016d1) |
| 2, current lineage | Added `primaryRegions`, including appearance and selection order. | [Region appearance](https://github.com/kyleve/Stuff/commit/acd0966b) |
| 3 | Added sample provenance and device records. The final version retained profiles, nickname history, and removal tombstones. Local consent and advisory check-ins stayed outside backups. | [Device work](https://github.com/kyleve/Stuff/commit/60421db77b6e2cd738d8aa2837981fdc63a2f16a) |
| 4 | Expanded device kinds, grouped metadata fields under `payload`, and renamed `registrationEpochID` to `registrationGenerationID`. | [Wire version](https://github.com/kyleve/Stuff/commit/9190535a5b482c1558840fed988e58b2f2e1ef3c) |
| 5 | Added `plannedStayRecords`, including clearing tombstones. | [Annual forecasts](https://github.com/kyleve/Stuff/commit/c2dbdf90b3e88e11e32de8bf76d7a41ac617130f) |
| 6 | Added optional sample motion and immutable attribution revisions. | [Sample corrections](https://github.com/kyleve/Stuff/commit/0da3b36dbce465edd93380993c7f2e13f718ebf8) |
| 7 | Adds independent stay identities, arrival/departure windows, and `homeRegionRecords`. | [`BackupArchive.swift`](Sources/Backup/BackupArchive.swift) |
| 8 | Adds Canadian province and territory IDs to the region values a writer can store. | [`BackupArchive.swift`](Sources/Backup/BackupArchive.swift) |
| 9 | Requires a capture installation on every GPS observation and an author on every sample-attribution revision. | [Version 9 contents](#version-9-contents) |
| 10 | Adds an immutable hardware-model event for every device profile. | [Version 10 contents](#version-10-contents) |
| 11 | Identifies the device behind each retained manual entry, evidence item, assertion, dismissal, forecast revision and primary region. | [Version 11 contents](#version-11-contents) |

The device feature also used prototype versions 4–7 before its merge.
Those versions described recording assignments, registration epochs, causal parents, and merge barriers.
The [prototype commit](https://github.com/kyleve/Stuff/commit/3b5dfaca728cb8023e2c02bccfbd52bb0738449a)
records that sequence. It is separate from the current version 4–7 lineage.
A version number alone does not identify every historical development archive.

The external upgrader recognizes supported older field shapes.
It normalizes dates, day identities, region keys, and dismissal URLs.
It supplies missing collections and converts older device payloads.
It excludes obsolete recording policies and non-restorable check-ins.
It never restores local recording consent.

## Version 6 contents

Version 6 adds optional `motion` to each raw location sample. Its `speed` holds
meters per second and its accuracy; its `altitude` holds meters and vertical
accuracy. Missing or invalid system readings become absent values. Accuracy
and coordinate observations remain raw, independent of later corrections.
The callback adapter follows Apple's [speed accuracy](https://developer.apple.com/documentation/corelocation/cllocation/speedaccuracy)
and [vertical accuracy](https://developer.apple.com/documentation/corelocation/cllocation/verticalaccuracy)
rules: speed accuracy may be zero; vertical accuracy must be positive.

The new `sampleAttributionRevisions` array preserves every immutable revision:

| Field | Meaning |
| --- | --- |
| `id` | Revision UUID, preserved by Merge and Replace |
| `sampleID` | Raw location sample UUID; delivery may precede the sample |
| `updatedAt` | Original revision timestamp |
| `replacementRegions` | Absent/null restores GPS; `[]` excludes; a set replaces attribution |

Effective attribution takes the latest timestamp, breaking ties by revision UUID.
Reset writes a newer nil replacement. Export includes superseded revisions and
reset tombstones in the active data generation, even when their sample is absent.
Raw samples and evidence assets are never rewritten by a GPS correction.

Merge retains exact revision identities and timestamps. Replace restores archive
corrections into the new data generation, while preserving device-removal
tombstones and local recording consent through the existing import lifecycle.
Old-generation local corrections do not leak into the replacement dataset.

Upgrading v1–v5 retains all existing records and assets, records unknown motion,
and adds empty correction history. The upgrade driver checks ZIP integrity and
record counts, then loads the result and its assets through the production
decoder using `./test`. The original input remains unchanged.

## Version 7 contents

Each `plannedStayRecords` revision names its stable `stayID`. Its optional value holds
that same identity, a region, and inclusive arrival and departure windows.
A nil value deletes that stay. Completed stays and deletion tombstones remain in the archive.

The `homeRegionRecords` array preserves forecast Home choices and their revision identities.
A nil region selects historical estimates. Both import strategies retain every planning revision.

The offline upgrader converts the singular v5/v6 stay register into one shared legacy identity.
It infers exact arrival from the revision's UTC Gregorian day, capped at the existing departure.
It preserves revision IDs, timestamps, motion readings, correction history, and assets.
The earlier itinerary prototype also used v6. Records with `stayID` retain their independent identities and date windows.

## Version 8 contents

Canadian subdivisions use stable IDs such as `ca-ON` in the existing region fields.
For example, a manual-only backup can record Ontario without any tracked regions or GPS samples.
An older store can omit that ID when reading a manual day. Version 8 makes the older importer reject
the archive before it changes any rows. This protection also applies when a ZIP moves to another account.

Upgrading a current-lineage v7 backup to v8 changes only its format version and preserves
the IDs in the archive. The current catalog accepts Canadian provinces and territories as
tracking choices. The account-wide data version is checked separately when the app opens synced history.

## Version 9 contents

A GPS sample stores the installation that observed it in `recordingDeviceID`.
Each sample-attribution revision stores the installation that made the correction
in `changedByDeviceID`, including exclusions and resets. Both fields use
`store://devices/<uuid>`. If a tablet corrects a phone's fix, Merge and Replace
preserve both original IDs. A revision can arrive before its sample or either
device profile. Manual and evidence-implied samples keep their original values.

The offline upgrader fills missing origins in v1–v8 single-phone archives. It preserves
existing capture and author IDs, immutable profiles, raw observations, timestamps,
region values such as `ca-ON`, and evidence bytes. A matching record with the same
UUID can supply its own origin. Otherwise, the upgrader uses the single installation
identified by the archive's profile, samples, or device and correction history.
Version 11 also covers manual-only archives. See the [retained action fields](#version-11-contents).

When the archive contains several possible installations, select the original
phone. Save its existing installation ID in a JSON file such as `original-phone.json`.
If the archive predates device profiles and contains no usable installation ID,
supply the full profile. This illustrative profile uses the initial registration
generation and a Unix timestamp in seconds.

```json
{
  "id": "store://devices/50a308e2-1630-41c1-af3c-b42e8b1c4588",
  "systemName": "Original iPhone",
  "kind": { "phone": {} },
  "registeredAt": 1698796800,
  "registrationGenerationID": { "rawValue": "00000000-0000-0000-0000-0000000000E0" }
}
```

Use the original profile if available. If you must supply a historical identity
for a phone that never had one, choose its UUID once and retain the same descriptor
for all its backups. For an ID already present in records or profiles, a file
containing just its `id` field suffices, even if its profile has yet to sync. Conflicting immutable profile values stop conversion before
the output file is replaced. The upgrader adds a supplied profile only when it
uses that profile to fill a missing origin.

```sh
ruby .agents/skills/upgrade-where-backup/scripts/upgrade_and_verify.rb old.zip upgraded.zip --source-profile original-phone.json --device-models models.json
```

An archive declaring v9 or later must already carry the required origins. The production
decoder checks it before restoring any rows. Preserve the original ZIP and
verify a separate upgraded copy before replacing an old phone's store.

## Version 10 contents

Each immutable device profile has a hardware-model event in
`recordingDeviceMetadataChanges`. The payload field and its value key are both
`hardwareModelIdentifier`. The value is the original raw machine identifier, such
as `iPhone16,1`. The event targets and is authored by that installation, has
revision zero, and uses its profile’s registration timestamp. The event survives
Replace with its profile. Renames and nickname clears keep their existing IDs
and generation semantics. A removed profile still has a model fact.

Swift and the offline converter derive one UUIDv8 event ID for the installation.
They concatenate the UTF-8 bytes of `com.stuff.where.device-hardware-model.v1`
and the lowercase hyphenated installation UUID, hash the result with SHA-256,
and take the first 16 bytes with the UUIDv8 version and RFC variant bits set.
For installation `65000000-0000-0000-0000-000000000001`, the event ID is
`64347ff5-9708-8b3b-ab2c-b2043fe0ff4f`. Repeated upgrades and live registration
produce the same fact.

For an older archive, supply a JSON model map keyed by the **original installation
UUID**, with one entry for each profile missing its model fact. This illustrative
map supplies identifiers for two installations.

```json
{
  "50a308e2-1630-41c1-af3c-b42e8b1c4588": "iPhone16,1",
  "853cdc06-e235-44c7-86ca-3edd0f14aeef": "iPad14,5"
}
```

```sh
ruby .agents/skills/upgrade-where-backup/scripts/upgrade_and_verify.rb v9.zip v10.zip --device-models models.json
```

An older ZIP that also needs a historical source profile accepts both mapping
flags. An existing model fact supplies its own identifier. A supplied mapping
must agree with it. The
upgrader preserves profile values, original nickname history, GPS capture and
correction authors, and assets. A valid model fact that synced before its profile
can round-trip on its own. For a v10 input, a profile missing its hardware event
or any contradictory hardware fact fails validation, even with a map.

## Version 11 contents

Device IDs use `store://devices/<uuid>`. Merge and Replace retain each original
actor, including the actor of a revision whose value has been cleared.

| Archived record | Author field |
| --- | --- |
| Manual day, including an entry without audit details | `manualDays[].changedByDeviceID` |
| Evidence metadata, with or without attachment bytes | `evidence[].addedByDeviceID` |
| Manual or evidence-implied location point | `samples[].assertedByDeviceID` |
| Dismissed issue | `dismissedIssues[].dismissedByDeviceID` |
| Planned stay and forecast home revisions, including tombstones | `plannedStayRecords[].changedByDeviceID` and `homeRegionRecords[].changedByDeviceID` |
| Saved primary-region choice | `primaryRegions[].changedByDeviceID` |

GPS observations retain their capture ID and corrections retain their editor.
A manual point can also retain an older capture tag. Revisions resolve by their
existing timestamps and IDs. Each winning value carries its own actor. A linked
evidence item and its implied points share an author. A point can arrive before
the evidence or device profile.

The offline upgrader preserves every explicit actor. An immutable record with
the same identity can supply a missing actor. For a linked evidence item and
its points, any known adding or asserting installation supplies their shared
actor. Conflicting known actors stop conversion. A manual point’s historical
capture tag can identify its missing author. Other missing actors require one
unambiguous installation across the archive or an explicit source selection.

For a manual-only v10 archive with no device identity, supply the original
phone’s full [profile](#version-9-contents) and [hardware identifier](#version-10-contents).
Reuse the same files for overlapping backups. If an original actor is already
known, the ID-only selection works even before its profile arrives. When a
profile is added, its matching existing model event can supply the identifier.

```sh
ruby .agents/skills/upgrade-where-backup/scripts/upgrade_and_verify.rb v10.zip v11.zip --source-profile original-phone.json --device-models models.json
```

The converter checks each input against the roles required by its version.
A v9 GPS fix missing its recorder, a v10 registered profile missing its model
fact, or a v11 action missing its author fails even with mapping files. It
preserves original attachments, record values and the order of authored edits.

Older exports could serialize the default primary-region list just like an
explicit selection. They carry no marker that distinguishes the two. During
upgrade, each exported region retains its order and appearance and acquires the
original installation’s ID. New v11 exports include the persisted choices and
leave the list empty when the picker is showing its synthesized defaults. A
nonempty Merge preserves those defaults on the destination. The importing
device authors only the extra default choices that the merge materializes.
An archived choice retains its original author even when it overlaps a default.
