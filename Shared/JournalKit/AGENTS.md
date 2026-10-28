# JournalKit – Module Shape

JournalKit is a generic append-only, crash-durable journal. It provides synchronous `Data` appends that survive process death, segment rotation under a byte budget, and torn-tail-tolerant recovery. See [`README.md`](README.md) for the API and durability model.

Read the root [`AGENTS.md`](../../AGENTS.md) first. That file owns the build system, formatting, and global conventions.

## Scope & dependencies

- **Use Foundation and os only.** Do not import logging types or Periscope. PeriscopeCore layers log semantics on top. Keep the journal payload-agnostic.

## Invariants

- **When `append` returns, the entry survives process death.** The write reaches the kernel page cache synchronously. `.full` extends coverage to kernel panics through `F_FULLFSYNC`. Do not buffer entries in user space.
- **Recovery never throws over a torn tail.** A crash can cut the file at any byte. Recovery yields every wholly-written entry and flags the tear. Keep the truncation fuzz in `JournalRecoveryTests` passing at every cut point.
- **A torn write poisons only its own segment.** A partial `write(2)` (disk-full's shape) leaves bytes recovery stops at. Mark the segment poisoned. Rotate to a fresh segment on the next append. Later entries must never land behind a tear.
- **Drop whole segments, oldest first.** Always expose drops (`droppedSegmentCount`, `droppedOlderEntries`). Never sacrifice the newest entries. If a segment fails to delete, keep it in the byte accounting. Later rotations retry it. The drop loop moves to the next-oldest segment so the budget still wins.

## Testing

Swift Testing lives in [`Tests/`](Tests), hosted in `StuffTestHost` (`JournalKitTests`). Journal into per-test temporary directories. Construct crashed-journal states (truncation, corruption) directly on disk.
