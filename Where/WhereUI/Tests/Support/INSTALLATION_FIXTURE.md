# Installation lifecycle fixture

The [design contract](../../../MULTI_DEVICE_RECORDING.md#device-identity-and-setup) defines identity and consent behavior.
[`InstallationRecordingContextStoreTests`](../InstallationRecordingContextStoreTests.swift) drives the fixture through production recovery, launch, compatibility, import, and store code.

[`InstallationLifecycleFixture`](InstallationLifecycleFixture.swift) creates an isolated installation with separate resources:

| Resource | Lifetime |
| --- | --- |
| Scripted Keychain | Belongs to one simulated physical phone. It is separate from app files. |
| Installation sidecar and compatibility cache | Production file adapters create these files and set their backup-exclusion attributes. |
| Pending shared items | The production queue retains complete drafts in its backup-excluded directory. |
| Preferences | A property-list adapter stores real `WherePreferences` values in a backed-up file. |
| Raw history | A temporary SQLite store uses the production SwiftData schema and value-store implementation. |
| Shared compatibility head | A separate conditional database survives process replacement, reinstall, restore, and transfer. |

Each process replacement constructs fresh adapters and services.
The fixture retires scoped services before copying files or ending a process.
Restored files use a fresh directory so old SQLite connections cannot modify the restored installation.
A release regression checks that stopped process owners do not retain their dataset.

## Backup and Keychain assumptions

[`InstallationBackupFixture`](InstallationBackupFixture.swift) copies files according to their actual `isExcludedFromBackup` attributes.
It has no path-based exclusion list.
The capture represents an atomic backup of a quiescent installation.
Preferences and SQLite history transfer; the Keychain resource does not enter the backup.

The fixture assumes the platform honors backup exclusion and the Keychain's device-only accessibility class.
Restore and direct transfer use that same nonmigration boundary.
Keychain survival on the same phone, absence, and access failure are separate scripted inputs.
These tests do not measure physical-device backup, transfer, or Keychain behavior.

## Shared-account assumptions

[`InstallationSharedAccount`](InstallationSharedAccount.swift) implements the database protocol beneath `CloudKitDataCompatibilityTransport`.
The production verification and conditional-update algorithm runs unchanged.
The adapter holds competing initial saves before either commits, checks revisions, and can lose a committed save's response.
For offline tests, account identity remains available while shared reads and writes fail.
Other identity-failure cases remain covered by the coordinator's focused tests.
Each phone has its own [account connection](InstallationAccountConnection.swift).
Changing one connection cannot change another phone's authentication or overwrite the previous account's control head.

[`InstallationHistoryDelivery`](InstallationHistoryDelivery.swift) supplies controlled batches at the committed-record boundary.
It uses production store writers and the scripted remote-change source.
Tests can deliver duplicate observations, delay profiles, or deliver an unsupported record before the shared control head changes.
The adapter does not model CloudKit transport or conflict resolution.

Durable source decisions extend this fixture in their owning slice.
Their recovery tests must preserve existing operation identities and allocate a distinct identity for each new operation.
