# Store perform serialization

Confirmatory model for [`SwiftDataStore.perform`](../../WhereCore/Sources/Persistence/SwiftDataStore.swift).
At most one outermost transaction runs at a time.
Nested same-task calls reuse the transaction.
Waiters proceed in FIFO order.

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
