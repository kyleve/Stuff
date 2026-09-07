# Store perform serialization

Confirmatory model for [`SwiftDataStore.perform`](../../WhereCore/Sources/Persistence/SwiftDataStore.swift):
at most one outermost transaction, nested same-task reuse, FIFO waiters.

## Correspondence

| Model | Production |
| --- | --- |
| `isTransacting` | exclusive gate |
| `waiterCount` | `transactionWaiters` |
| `taskAPhase` / `taskBPhase` | concurrent outer callers |
| `nestedDepth` | `@TaskLocal activeTransactionStores` reuse |

## Properties

- `AtMostOneOutermost`
- `NestedSameTaskNoWait`

## Result

**Verified for these model bounds and assumptions** on `Current.cfg`.
`Broken.cfg` (concurrent outermost without waiting) falsifies `AtMostOneOutermost`.

Swift guard: [`SwiftDataStoreTests.concurrentOutermostPerformsSerializeAndAllCommit`](../../WhereCore/Tests/SwiftDataStoreTests.swift).

Run: `./tla-check StorePerformSerialization`
