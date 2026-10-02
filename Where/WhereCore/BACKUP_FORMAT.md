# Where backup format v7

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
| 7 | Added the required data compatibility level. Operational capability reports remain excluded. | [Compatibility gate](https://github.com/kyleve/Stuff/pull/329) |

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

## Version 7 contents

Version 7 adds `requiredDataCompatibilityVersion`, a positive integer. Export
records the shared store's resolved requirement. Import rejects unsupported
requirements before pausing recording or writing recovery state. A supported
increase uses the device-readiness review and explicit override. Merge and
Replace preserve the greater of the existing and imported requirements.
Device capability reports and recording check-ins are not restorable data.

Upgrading v1–v6 assigns compatibility version 1. Upgrading v7 preserves its
requirement and rejects a missing or invalid value.

## Version 6 contents

Version 6 adds optional `motion` to each raw location sample. Its `speed` holds
meters per second and its accuracy; its `altitude` holds meters and vertical
accuracy. Missing or invalid system readings become absent values. Accuracy
and coordinate observations remain raw, independent of later corrections.
The callback adapter follows Apple's [speed accuracy](https://developer.apple.com/documentation/corelocation/cllocation/speedaccuracy)
and [vertical accuracy](https://developer.apple.com/documentation/corelocation/cllocation/verticalaccuracy)
rules: speed accuracy may be zero; vertical accuracy must be positive.

The `sampleAttributionRevisions` array preserves every immutable revision:

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
