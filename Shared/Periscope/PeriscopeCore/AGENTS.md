# PeriscopeCore – Module Shape

PeriscopeCore is the core of the **Periscope** observability framework: typed
`Codable` log events, the `Log<Event>` scope hierarchy, tags, spans, the sink
pipeline, ambient event sources, and the SwiftData store. See
[`README.md`](README.md) for the narrative and API.

This file complements the root [`AGENTS.md`](../../../AGENTS.md), which owns
the build system, formatting, and global conventions. Read that first.

## Scope & dependencies

- **Foundation + os + SwiftData + Network + JournalKit only** (plus the
  ObjectiveC runtime, solely for `LogContextProviding`'s deallocation
  trackers). No SwiftUI, no app code, no LogKit. UIKit is allowed **only**
  inside `#if canImport(UIKit)` (ambient sources, the image-attachment
  convenience).
- Layering: `PeriscopeUI` and `PeriscopeTools` depend on this module — never
  the reverse.

## Invariants

- **Emitting never blocks the caller.** Log calls append to a lock-guarded
  buffer synchronously; sinks (OSLog, SwiftData) drain asynchronously, and
  sink delivery order is emission order with scope definitions first.
  Live streams see buffered order too: observer yields happen *under* the
  state lock (yields only buffer) — yielding outside it would let racing
  emitters invert live delivery, e.g. a span's end before its began.
- **Scope IDs are deterministic** (hash of parent + name) — the same path is
  the same scope across processes and launches; `begin`/`end` span pairing
  and cross-layer links rely on this.
- **Persistence must retain the full hierarchy** — events reference scopes
  many-to-many (links), and scopes keep their parent chain.
- **Custom levels are values, not cases.** `LogLevel` is a struct ordered by
  `severity`; never switch exhaustively over "all" levels.
- **Sink failures never propagate or vanish** — the store logs them to
  OSLog, counts them, and persists a synthetic `StoreWriteFailed` marker
  for the lost batch; the pipeline reports drops with a synthetic
  `DroppedEvents` record.
- **A failed store save must roll back** (`recoverFromFailedWrite`):
  the context is discarded, row caches drop, and the session row refetches
  by identity — one poisoned batch must never wedge subsequent saves or
  fork the session.
- **The crash journal is synchronous at emit and silent on failure.**
  Every buffered record appends to the journal (when an on-disk store is
  attached) *before* `record()` returns — sequence stamped under the state
  lock, file I/O outside it, fault+ records `F_FULLFSYNC`. Journal failures
  count and log to OSLog but never throw into the emit path. Ingest runs
  *before* `startSession` so recovered begans join the orphan sweep; a
  journal that fails ingest stays for the next launch.
- **Only app processes ingest journals.** App extensions journal their own
  sessions but skip ingest (ingest deletes journals; an extension launch
  must not eat the live app's) — the app's next launch recovers everyone's.
  Sharing one on-disk store across *concurrently live* processes is not
  yet supported; see [`TODOs.md`](../TODOs.md).
- **Payloads persist as versioned JSON** (`eventName` + `eventVersion`), not
  per-event schemas — changing an event's shape must not require a SwiftData
  migration.
- **Every span eventually ends, and its began is delivered first.**
  `measure` closes on every path (including throw/cancellation); bounded
  spans expire via the watchdog; re-begins supersede rather than refuse;
  relaunch orphan-closes `endsWithProcess` spans. Don't add a span path
  that can leave `openSpans` growing forever (`survivesRelaunch` resume is
  the one staged exception — see [`TODOs.md`](../TODOs.md)). Registration
  and the `SpanBegan` record land atomically (`LogRecorder.beginSpan`), so
  a span is never closable before its began is in the pipeline; the
  overflow drop policy never splits a recorded pair
  (`LogEvent.isProtectedFromDropping`, an event-type opt-in the span pair
  events set); and redaction is transform-only
  for pair records (suppression falls back to a stripped copy). Keep all
  three.
- **Span pairs floor together.** The floor decision is made once, at
  begin, and the whole lifecycle follows it (`OpenSpan.beganRecorded`,
  `LogRecord.bypassesFloors`): a recorded began always gets its end —
  normal, expired, or superseded — even if floors rise mid-span, and a
  floored began silences the entire span (overdue sentinel included).
  Never a dangling half.

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost`
(`PeriscopeCoreTests`). Use in-memory stores, fresh `Periscope` systems per
test (never the shared singleton), and injected clocks. Note that
`Log<Event>()` defaults to `.shared` — a deliberate ergonomics exception to
the no-Core-defaults rule — so tests must always pass `system:` explicitly.
