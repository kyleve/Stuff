# Where backup format v6

`BackupArchive` is the authoritative manifest schema. A ZIP contains its JSON
manifest and the referenced evidence assets. The production `BackupService`
decoder accepts the current version only; upgrade older archives with
[`Where/Tools/upgrade-backup.rb`](../Tools/upgrade-backup.rb).

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
