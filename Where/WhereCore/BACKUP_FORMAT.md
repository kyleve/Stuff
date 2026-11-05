# Where backup format v9

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
| 8 | Preserves recording-day context and versioned controls, declares the required data major, and uses Foundation's 2001 date epoch. | [`BackupArchive.swift`](Sources/Backup/BackupArchive.swift) |
| 9 | Adds ongoing place validity and its explicit interval envelope scope. Finite place payloads retain their original bytes. | [`RecordingInterval.swift`](Sources/Devices/RecordingInterval.swift) |

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

Version 9 place envelopes use `intervals` scope. Each interval has a start and an optional exclusive end.
An absent end means ongoing validity. Regular homes permit this scope; temporary bases require an end.
The offline upgrader changes known major-one place envelopes from `periods` to `intervals` without changing their payloads or identities.
Other control scopes and opaque records remain unchanged.

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

All JSON `Date` values use numeric seconds since 2001-01-01 UTC, including envelope scopes.
This preserves each Foundation `Date` exactly through export and reimport.
Unix-epoch conversion can lose precision and change immutable observations or their recording day.
The upgrader converts older timestamps before assigning recording days. Opaque control payload bytes remain unchanged.

`requiredDataMajor` declares the history contract. The decoder admits this header before decoding history.
`versionedHistoryRecords` retains source choices, ignore intervals, places, calendar context, and unknown control payloads.
Each envelope retains its identity, authoring version, affected scope, causal dependencies, and original payload bytes.

GPS observations in major 1 require a recording device and `recordingDay`.
A resolved assignment contains the logical day, zone identifier, and captured UTC offset.
An unresolved assignment explicitly records missing historical context.
Import preserves these values. It never substitutes the importing phone's identity or calendar.

Merge preserves operation identities and bytes. Replace rebinds envelopes to the new data generation without changing their contents.
Neither strategy lowers the dataset's compatibility requirement or activates a newer contract.
Import requires an admitted session with the same required major as the archive.

### Convert historical GPS

A format-only upgrade preserves the existing data major. Archives before version 8 remain major 0.
Use `--recording-map` to prepare history for major 1:

```sh
mise exec -- ruby Where/Tools/upgrade-backup.rb original.zip converted.zip --recording-map recording-map.json
```

The mapping keys are stable sample UUIDs. Reuse the same mapping across exports containing the same samples.
Supply a historical device UUID for each unattributed GPS observation.
Supply calendar context for each observation without a saved assignment:

```json
{
  "samples": {
    "11111111-1111-1111-1111-111111111111": {
      "recordingDeviceID": "22222222-2222-2222-2222-222222222222",
      "calendar": {
        "timeZone": "America/New_York",
        "secondsFromGMT": -18000
      }
    }
  }
}
```

Use the offset that applied to that observation. The converter calculates its logical date from the timestamp and supplied offset.
It does not recalculate the offset through the current time-zone database.
If historical context is unavailable, use `"calendar": {"unresolved": true}`. That history requires later clarification before automatic selection.
Existing device attribution and recording-day assignments must agree with any supplied mapping.
Missing mappings stop conversion before output replacement. The original archive remains unchanged, including after a failed conversion.

The shared `Tests/Fixtures/RecordingBackup` fixture checks this wire format through Ruby conversion and the production Swift decoder.
The stack still uses major 0. Major 1 import and selection require the remaining activation gates in the [design](../MULTI_DEVICE_RECORDING.md).
