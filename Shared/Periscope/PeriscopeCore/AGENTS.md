# PeriscopeCore – Module Shape

PeriscopeCore is the core of the **Periscope** observability framework: typed
`Codable` log events, the `Log<Event>` scope hierarchy, tags, spans, the sink
pipeline, ambient event sources, and the SwiftData store. See
[`README.md`](README.md) for the narrative and API.

This file complements the root [`AGENTS.md`](../../../AGENTS.md), which owns
the build system, formatting, and global conventions. Read that first.

## Scope & dependencies

- **Foundation + os + SwiftData + Network + CryptoKit + JournalKit only**
  (plus the ObjectiveC runtime for deallocation trackers and target/selector
  observation; CryptoKit is used only by `ScopeID.swift`). No SwiftUI, no app
  code. UIKit only inside `#if canImport(UIKit)`.
- Layering: `PeriscopeUI` and `PeriscopeTools` depend on this module — never
  the reverse.

## Invariants

- **Emitting never blocks the caller.** Log calls append to a lock-guarded
  buffer synchronously; sinks drain asynchronously in emission order, scope
  definitions first. Observer yields happen *under* the state lock — yielding
  outside it lets racing emitters invert live delivery (a span's end before
  its began).
- **Scope IDs are deterministic** (hash of parent + name) — span pairing and
  cross-layer links rely on the same path being the same scope across
  processes and launches.
- **`sequence` is store-global and monotonic**, resuming past the highest
  stored value across launches — that is what makes `LogQuery.afterSequence`
  a valid incremental cursor.
- **Persistence retains the full hierarchy** — events reference scopes
  many-to-many, and scopes keep their parent chain.
- **Custom levels are values, not cases.** `LogLevel` is a struct ordered by
  `severity`; never switch exhaustively over "all" levels.
- **Ambient sources log change-only where the signal is chatty**
  (`NetworkPathAmbientSource` dedupes `NWPathMonitor`'s repeat callbacks);
  notification-based sources are deliberately *not* deduped — each repeated
  memory warning is a distinct event.
- **Sink failures never propagate or vanish** — logged to OSLog, counted, and
  persisted as a synthetic `StoreWriteFailed` marker; the pipeline reports
  drops with a synthetic `DroppedEvents` record.
- **A failed store save rolls back** (`recoverFromFailedWrite`) — one
  poisoned batch must never wedge subsequent saves or fork the session.
- **The crash journal is synchronous at emit and silent on failure.** Every
  buffered record appends before `record()` returns (sequence stamped under
  the state lock, file I/O outside it, fault+ records `F_FULLFSYNC`); journal
  failures count and log but never throw into the emit path. Ingest runs
  *before* `startSession` so recovered begans join the orphan sweep; a
  journal that fails ingest stays for the next launch.
- **Only app processes ingest journals** — extensions journal their own
  sessions but skip ingest (ingest deletes journals; an extension launch must
  not eat the live app's). Concurrently live processes sharing one on-disk
  store is unsupported; see [`TODOs.md`](../TODOs.md).
- **Payloads persist as versioned JSON** (`eventName` + `eventVersion`) — an
  event shape change must not require a SwiftData migration.
- **Every span eventually ends, and its began is delivered first.** `measure`
  closes on every path; bounded spans expire via the watchdog; re-begins
  supersede; relaunch orphan-closes `endsWithProcess` spans (the
  `survivesRelaunch` resume is staged — [`TODOs.md`](../TODOs.md)). Keep all
  three protections: begin registration + `SpanBegan` record land atomically
  (`LogRecorder.beginSpan`); the overflow drop policy never splits a recorded
  pair (`LogEvent.isProtectedFromDropping`); redaction is transform-only for
  pair records.
- **Span pairs floor together.** The floor decision is made once, at begin
  (`OpenSpan.beganRecorded`, `LogRecord.bypassesFloors`): a recorded began
  always gets its end, and a floored began silences the entire span — never a
  dangling half.

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost`
(`PeriscopeCoreTests`). Use in-memory stores, fresh `Periscope` systems per
test (never the shared singleton), and injected clocks. `Log<Event>()`
defaults to `.shared` — a deliberate ergonomics exception to the
no-Core-defaults rule — so tests must always pass `system:` explicitly.
