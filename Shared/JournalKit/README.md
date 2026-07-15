# JournalKit

An append-only, crash-durable journal of opaque `Data` entries — the
write-ahead net for anything that must survive the process dying
mid-flight. Periscope uses it as its log journal; the implementation is
payload-agnostic and has no logging knowledge.

## Quick start

```swift
import JournalKit

// Writing (synchronous, any thread; ~microseconds per append):
let journal = try Journal(
    directory: journalDirectory,
    configuration: Journal.Configuration(maximumByteCount: 8 * 1024 * 1024),
)
try journal.append(encodedEntry, sync: .processDeath)
try journal.append(direEntry, sync: .full)   // F_FULLFSYNC — milliseconds

// Recovery (the next launch):
let recovered = try JournalRecovery.recover(directory: journalDirectory)
for payload in recovered.payloads { ingest(payload) }
try JournalRecovery.remove(directory: journalDirectory)
```

## Durability model

- **`.processDeath`** (the default posture): once `append` returns, the
  entry is in the kernel page cache and survives the *process* dying by any
  means — crash, `SIGKILL`, jetsam. Cost: single-digit microseconds.
  Verified empirically by the SIGKILL harness in
  [`Shared/Periscope/Prototypes/JournalBenchmark`](../Periscope/Prototypes/JournalBenchmark).
- **`.full`**: `F_FULLFSYNC` before returning — survives kernel panics and
  power loss. Milliseconds; reserve for entries that warrant it.

## How it works

Entries are framed `[UInt32 length][UInt32 crc32][payload]` and appended to
numbered segment files. Segments rotate at half the byte budget, and the
oldest segment drops whole when the budget overflows — the journal favors
the newest entries, like a flight recorder, and reports
`droppedSegmentCount` / `droppedOlderEntries` so callers can surface the
gap. An optional `segmentHeader` re-writes as the first entry of every
segment, so identity/context entries survive any amount of rotation
(recovery returns one copy per surviving segment). A *partial* write
poisons its segment and the next append rotates, so torn bytes never
strand later entries.

Recovery reads segments in order and validates each entry's length and CRC.
A torn or corrupt entry ends that segment's recovery and sets
`foundTornEntry` — the partial final entry a crash leaves is expected, and
recovery never throws over it.

## Contracts & limitations

- Entry ordering across concurrent appenders is append order (writers
  serialize on an internal lock); per-writer order is preserved. Any
  cross-entry semantics — sequencing, deduplication, schemas — belong to
  the caller's payloads.
- One `Journal` instance per directory at a time; reopening continues after
  the existing segments rather than overwriting them.
- CRC-32 catches torn and corrupt entries; it is integrity checking, not
  authentication.
