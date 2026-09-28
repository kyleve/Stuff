# Automatic backup retention

This model checks atomic storage fallback and the authority to delete an old archive.
It separates enumeration, authentication, and deletion because each observes files
at a different time.

## Source correspondence

| Model state or action | Swift boundary |
| --- | --- |
| `CloudWriteStep`, `LocalWriteStep`, `copies` | `AutomaticBackupStorage.store` commits a file by atomic move; only a failed cloud write permits local fallback |
| `MaintenanceFailureStep` | Catalog or retention failure after a successful write does not trigger another export |
| `EnumerateStep`, `pending` | `catalog()` enumerates accessible roots and returns timestamp-ordered files |
| `ValidateStep`, `verified`, `hashes` | `reconcileRetention` selects the envelope key, authenticates the archive, and records its full-file digest |
| `Keepers`, `Candidates` | `AutomaticBackupRetention.prune` sorts authenticated timestamps and selects the newest three |
| `ChangeFileStep`, `revision` | A file changes after an earlier validation read |
| `ChangeAvailabilityStep` | The installation loses or regains access to its iCloud root |
| `PruneStep` | One coordinated operation verifies candidate and keeper digests before deleting the candidate |

Valid file tokens are ordered by their authenticated export timestamp.
The model also includes an unknown-key file and a forged future-dated envelope.
Enumeration uses descending order, matching the catalog. This avoids exploring
irrelevant permutations of the same validation queue.

## Safety properties

- `PreserveUnknownFiles`: unknown keys and unrecognized files are not deleted.
- `PreserveChangedCandidates`: a changed candidate is not deleted using stale validation.
- `DeletionLeavesThreeHealthyFiles`: each deletion leaves at least three verified, accessible backups.
- `NoDuplicateFallback`: a committed cloud export is not also written locally.
- `TypeOK`: every model variable remains within its declared domain.

The third property constrains the deletion action, not arbitrary external events.
External deletion or corruption can independently reduce the number of good files.
The application must not make that situation worse through stale pruning authority.

## Counterexample and Swift correction

The `review` control represents candidate-only revalidation from commit `0ae38ee1`.
Its shortest trace has 12 states:

1. Commit a fourth valid backup.
2. Enumerate and authenticate all four backups.
3. Change one of the newest three files.
4. Recheck and delete the unchanged oldest file.

Only two healthy backups remain. The previous implementation rechecked the
file being deleted, but did not recheck its replacements.

`AutomaticBackupRetention.prune` now acquires the three keeper reads and candidate
deletion together through `NSFileAccessIntent`. It checks all four digests inside
that accessor. A missing or changed keeper prevents the deletion.
`AutomaticBackupRetentionTests` replays changed-keeper, missing-keeper, and changed-candidate cases.

## Bounds and limitations

The bounds are one or two installations, three initial healthy cloud archives,
one new export per installation, two untrusted files, and one external mutation.
Each installation can lose and regain cloud access once.
Local fallback belongs only to its installation.

The passing cases check `EventuallySettled` under weak fairness for writes,
enumeration, validation, and deletion. File operations must eventually return.
They may fail. The model does not claim that iCloud always becomes available.
Explicit idle stuttering permits a live process after the bounded work finishes.

The coordinated deletion action assumes a consistent local filesystem view.
It represents participating file coordinators on one system, not a distributed
transaction across iCloud replicas. Delayed replica deletions, remote conflict
resolution, uncoordinated external writes, and permanent disk loss are excluded.
The two-installation case exercises overlapping maintenance against this shared-view abstraction.
It does not prove globally exact three-file retention during a network partition.

Encryption and ZIP validation are abstract predicates. Swift archive tests check
the real format. The separate catalog regressions check eviction preflight,
cancellation, and partial listings; this model does not emulate Foundation I/O.

## Controls and results

The checked candidate state spaces on 2026-09-07 were:

| Case | Generated / distinct states | Depth |
| --- | ---: | ---: |
| `candidate` | 6,010 / 2,016 | 17 |
| `candidate-two-devices` | 11,133,064 / 2,661,340 | 34 |

`unauthenticated` lets forged future-dated envelopes displace healthy files.
`retry-on-maintenance` writes a second copy after a cloud commit.
`stale-candidate` deletes a candidate after its bytes change.
Each negative control must violate its named invariant.
The reachability control must find an external mutation, a maintenance failure,
and an actual deletion in the same execution.

## Run

```sh
./tla-check AutomaticBackupRetention
```

See the [specification workflow](../README.md) for artifacts and pinned tools.
The larger case takes several minutes. Recheck the mapping after changing
coordination, fallback, authentication, or retention selection.
