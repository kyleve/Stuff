# Compatibility access lifetime

Run `./tla-check CompatibilityWrites`.

This bounded model checks one scope's reads and writes across retirement.
It adapts the old authority stack's write model without recording ownership.
It adds the lock between the final access check and the physical save.

## Source correspondence

| Model action or state | Swift boundary |
| --- | --- |
| `Begin`, `StartRead` | `DataAccessPermit.withAccess` checks entry and installs the task-local permit. |
| `pending` | A `CompatibilityScopedStore.perform` body can suspend with staged changes. |
| `AcquireCommit` | `DataAccessPermit.commitWhileValid` acquires the mutex and checks revocation. |
| `PhysicalSave` | `SwiftDataStore.perform` saves its private context while the permit mutex stays locked. |
| `ReleaseCommit` | The synchronous save closure returns and releases the mutex. |
| `Revoke` | `DataAccessPermit.revoke` uses the same mutex. |
| `ValidateReadExit` | `withAccess` validates access after the operation returns. |
| `FreshScope` | A later scope must construct a new permit. The old permit has no restore operation. |

Swift regressions hold a transaction or snapshot at a known suspension boundary.
See `SwiftDataStoreTests.revokedScopeCannotCommitASuspendedTransaction`, `CompatibilityScopedStoreTests`, and `DataAccessPermitTests`.
The scoped wrapper checks individual reads as well as snapshots and transactions.
Nested operations may reuse the same permit but cannot replace it with another scope's permit.

## Bounds and assumptions

The model has one old writer, one old reader, one retirement, and one new-scope write.
The physical save is synchronous and either succeeds or throws before returning.
The mutex orders the save against revocation on other executors.
Retirement can happen after a successful save but before its caller receives the result.
The caller can then receive an access error for a write that already committed.

This is a safety model. It claims no network or scheduling liveness.
The stuttering process keeps completed executions available without a deadlock claim.
It excludes account identity, shared verification, version admission, notification delivery, and published output.
Those parts of the [compatibility slice](../../MULTI_DEVICE_RECORDING.md#3-compatibility-gate) still require their own implementation and correspondence review.
The current app does not yet construct a compatibility scope in production.
The scoped wrapper must own the outermost transaction; the model does not cover a raw outer transaction with only a scoped inner call.
The read-completion check is a local access check. It cannot fence publication of values that have already returned.
Revocation can happen after this check releases its lock and before the caller receives or uses the result.

## Controls

The passing case checks that retired scopes cannot commit or pass the read-completion check.
It also checks that recovery leaves the old permit revoked.
The current configuration explores 75 distinct states.

Three negative cases remove the commit lock, reuse the retired permit, or omit read-result validation.
Each must fail its named invariant.
The reachability control requires a suspended write to be rejected and a fresh scope to commit afterward.
