# JournalKit – Module Shape

JournalKit is the generic append-only, crash-durable journal: synchronous
`Data` appends that survive process death, segment rotation under a byte
budget, and torn-tail-tolerant recovery. See [`README.md`](README.md) for
the API and durability model.

This file complements the root [`AGENTS.md`](../../AGENTS.md), which owns
the build system, formatting, and global conventions. Read that first.

## Scope & dependencies

- **Foundation + os only.** No logging types, no Periscope imports — the
  journal is payload-agnostic by design (PeriscopeCore layers log semantics
  on top). Keep it that way.

## Invariants

- **`append` returning means the entry survives process death.** The write
  reaches the kernel page cache synchronously; `.full` extends coverage to
  kernel panics via `F_FULLFSYNC`. Nothing may buffer entries in user space.
- **Recovery never throws over a torn tail.** A crash can cut the file at
  any byte; recovery yields every wholly-written entry and flags the tear.
  The truncation fuzz in `JournalRecoveryTests` pins this at every cut
  point — keep it passing.
- **Drops are whole segments, oldest first,** and always observable
  (`droppedSegmentCount`, `droppedOlderEntries`) — the newest entries are
  never sacrificed.

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost`
(`JournalKitTests`). Tests journal into per-test temporary directories and
construct crashed-journal states (truncation, corruption) directly on disk.
