# JournalBenchmark

A standalone prototype measuring the candidate implementations for
Periscope's crash-durability journal — the synchronous write-ahead net that
closes the emit-to-sink loss window. **Not a shipping target**: it is not
wired into the root `Package.swift` or any scheme.

## Candidates

| Variant | What it is |
|---|---|
| `file` / `file-fsync` | Append-only file, length-prefixed entries, `write(2)` under a lock (± `fsync` per append) |
| `sqlite-normal` / `sqlite-full` | Raw SQLite C API, WAL, one autocommit insert per record (`synchronous=NORMAL` / `FULL`) |
| `grdb` | GRDB `DatabaseQueue`, WAL + `synchronous=NORMAL`, one write per record |
| `coredata` / `coredata-batched` | `NSManagedObjectContext.performAndWait` insert, `save()` per record / per 100 |
| `swiftdata` / `swiftdata-batched` | `ModelContext` under a lock, `save()` per record / per 100 |

Each run measures per-append latency distributions (single-threaded and
4-thread contended), throughput, and *actual* crash durability: a child
process appends 1050 records then `SIGKILL`s itself with no teardown; the
parent reopens the journal and counts what survived.

## Running

```bash
swift build -c release && ./.build/release/JournalBenchmark
```

## Results (2026-07-15, M-series macOS, release build)

Caveats: macOS NVMe/APFS, not iPhone storage — absolute numbers will shift
on device, relative ordering should not. Darwin `fsync` does not force
platter durability (that's `F_FULLFSYNC`); every variant here is measured
at its app-crash-durable configuration, which is the design target.

### Emit-path latency — 5000 records, ~350-byte JSON entries, single thread

| variant                | p50 µs | p90 µs | p99 µs | p99.9 µs | max µs | ops/s |
|------------------------|--------|--------|--------|----------|--------|-------|
| file                   | 1.3 | 3.0 | 4.7 | 8.1 | 40 | 559501 |
| file-fsync             | 18.2 | 27.0 | 38.1 | 78.9 | 229 | 51065 |
| sqlite-normal          | 6.7 | 13.0 | 15.9 | 2097.2 | 5697 | 80360 |
| sqlite-full            | 34.2 | 51.7 | 89.3 | 11326.1 | 15513 | 16512 |
| grdb                   | 12.9 | 18.9 | 22.5 | 2682.7 | 10480 | 49893 |
| coredata               | 53.8 | 66.0 | 166.0 | 3367.7 | 3857 | 15189 |
| coredata-batched       | 1.0 | 1.6 | 327.5 | 406.2 | 6409 | 150606 |
| swiftdata              | 166.9 | 184.2 | 2536.1 | 3465.8 | 4439 | 4753 |
| swiftdata-batched      | 3.5 | 4.4 | 2606.0 | 2920.4 | 7729 | 30253 |

### Contended — 4 threads emitting concurrently

| variant                | p50 µs | p90 µs | p99 µs | p99.9 µs | max µs | ops/s |
|------------------------|--------|--------|--------|----------|--------|-------|
| file ×4                | 3.0 | 38.2 | 134.8 | 258.2 | 363 | 278104 |
| file-fsync ×4          | 20.0 | 36.1 | 780.3 | 5041.2 | 39519 | 46297 |
| sqlite-normal ×4       | 15.8 | 22.4 | 37.3 | 2839.5 | 82845 | 43289 |
| sqlite-full ×4         | 36.5 | 54.2 | 103.0 | 16207.3 | 231106 | 15231 |
| grdb ×4                | 90.2 | 110.2 | 991.1 | 3473.9 | 13602 | 30710 |
| coredata ×4            | 206.5 | 217.1 | 996.6 | 3730.0 | 3880 | 16796 |
| coredata-batched ×4    | 17.0 | 20.2 | 385.4 | 1519.2 | 5581 | 108121 |
| swiftdata ×4           | 168.2 | 189.0 | 2443.3 | 3430.8 | 790598 | 4825 |
| swiftdata-batched ×4   | 5.5 | 56.4 | 2948.5 | 14690.2 | 28140 | 28980 |

### Durability — child SIGKILLs itself mid-stream (no teardown)

| variant                | recovered |
|------------------------|-----------|
| file                   | all 1050 |
| file-fsync             | all 1050 |
| sqlite-normal          | all 1050 |
| sqlite-full            | all 1050 |
| grdb                   | all 1050 |
| coredata               | all 1050 |
| coredata-batched       | 1000 of 1050 (lost 50) |
| swiftdata              | all 1050 |
| swiftdata-batched      | 1000 of 1050 (lost 50) |

## Reading

- Every **per-record-commit** variant survives SIGKILL fully — including
  unfsynced appends and `synchronous=NORMAL` WAL: page-cache writes survive
  process death, empirically. Both **batched** variants lose exactly their
  unsaved tail: the reopened window, made visible.
- The **file** append is the only variant whose worst case stays in
  microseconds (max 40µs single-threaded, 363µs contended). Every
  SQLite-backed variant — raw, GRDB, Core Data, SwiftData — has
  multi-millisecond tails on the emit path (WAL checkpoints, save
  machinery), i.e. an occasional log call that stalls for milliseconds.
- **SwiftData** per-record is the slowest by far (167µs median, 2.5ms p99,
  790ms contended max) and its context is not thread-safe; **Core Data**
  per-record is ~40× the file's median with millisecond tails.
