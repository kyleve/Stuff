# Recovery key publication

This model checks independent key creation, durable publication, and synchronization.
It asks whether synchronization can remove the last preserved secret for an
already published archive.

## Source correspondence

| Model state or action | Swift boundary |
| --- | --- |
| `unlocked` | The protected-data check before `BackupRecoveryKeyProvider.loadOrCreate` accesses Keychain |
| `ReadOrGenerateStep`, `chosen` | Read the installation's active key, or generate a candidate after an explicit missing-item result |
| `PreserveStep`, `ring` | `preserve(_:)` creates an immutable account in `KeychainCollection` |
| `PinStep`, `pin` | The non-synchronizing active-key item is created after preservation |
| `ExportStep`, `archives` | A returned recovery key is used by an automatic export |
| `SynchronizeStep` | Independent accounts arrive through iCloud Keychain without replacing another account |
| `CrashStep` | Process termination loses transient selection, but retains completed Keychain writes |
| `FailKeychainStep` | A failed preservation attempt returns without pinning or exporting |

The model splits synchronous Keychain calls into separate atomic steps.
Other processes and synchronization can act between those calls, even though
one Swift actor does not interleave its synchronous method body.
An acknowledged Keychain write is treated as durable.

`ring[d]` is the set currently known to installation `d`.
The local `pin[d]` is not a synchronized last-writer-wins register.
Cryptographic key bytes and account identifiers are represented by distinct tokens.

## Properties and assumptions

- `KeyPrecedesArchive`: the exporting installation preserved the key first.
- `RecoveryKeysSurviveSync`: every published archive's key remains in at least one durable collection.
- `PinnedKeyIsPreserved`: every active local key belongs to its local collection.
- `NoCreationBeforeUnlock`: neither preservation nor export occurs before unlock.
- `TypeOK`: every variable remains within its declared domain.

The liveness properties require every installation to finish an export and
eventually learn all keys. They assume eventual unlock, successful Keychain
retries, and eventual synchronization between reachable devices.
Safety does not require prompt synchronization. The model permits arbitrary
finite delay before each synchronization action.

The finite bounds are two or three installations, one candidate identity per
installation, at most one crash each, and at most one preservation failure each.
After a pre-pin crash, the model reuses that installation's abstract candidate.
It does not count abandoned random candidates or model local duplicate-item races.
The Swift tests cover duplicate creation, legacy-key preservation, malformed
items, and locked-item errors separately.

Account deletion, account sign-out, device erasure, Keychain rollback, identifier
collisions, cryptographic failures, and permanent loss of every device are excluded.
The model does not promise recovery before synchronization completes.
A copied recovery key remains the user's independent recovery option.

## Controls and results

The checked current state spaces on 2026-09-07 were:

| Case | Generated / distinct states | Depth |
| --- | ---: | ---: |
| `current` | 11,235 / 2,705 | 20 |
| `current-three-devices` | 6,743,923 / 863,441 | 30 |

`mutable-slot` replaces collection union with destructive slot replacement.
It must lose a published key. `publish-first` exports before preservation and
must violate `KeyPrecedesArchive`.
These are protocol mutations, not simulations of all historical implementation details.

The reachability control must find completed exports and synchronization after
both a crash and a failed Keychain attempt.
The existing Swift guard is
`BackupRecoveryKeyProviderTests.independentlyCreatedKeysRemainAvailableAfterSynchronization`.
No additional key-storage change was required by these bounded checks.

## Run

```sh
./tla-check RecoveryKeyPublication
```

See the [specification workflow](../README.md) for pinned tools and retained artifacts.
Recheck the mapping after changing preservation, active-key selection, or synchronization.
