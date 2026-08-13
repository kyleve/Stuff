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
- **An ambient event declares whether it's a state or an occurrence.**
  `AmbientEvent.reporting` decides whether the event folds into the
  `AmbientSnapshot` stamped on later records. A momentary signal (a memory
  warning) is `.occurrence` and never becomes state — folding it in would
  leave every subsequent record claiming the app was mid-memory-warning. A
  source whose signal *is* a lasting condition should also report it at
  `started()`, or the state is unknown until it next changes (thermal and
  low-power do; `AppLifecycleAmbientSource` deliberately doesn't — it has no
  way to know the phase it started in).
- **Ambient state is stamped at emit, not joined at read.** `Periscope.buffer`
  hands each record the snapshot in force at that moment, and a snapshot keeps
  its `id` until a `.state` event actually moves a value — which is what makes
  "one stored row per distinct state" true rather than one row per record.
  Anything that mutates the snapshot must preserve that: a new identity per
  record would multiply the rows by the log volume.
- **Folding outlives the admission gates.** An ambient `.state` event the
  level floors discard still folds into the running snapshot (floors route,
  they don't scrub); one that redaction *suppresses* clears its kind instead —
  folding it would smear the suppressed value onto every later record, and
  keeping the old value would lie. The snapshot must never go stale because
  the event itself was kept out of the record stream.
- **`remove(_:)` is `async` because it settles the sink first** — the in-flight
  drain is awaited and the sink flushed, so a removed sink is owed nothing and
  hears nothing more. Removing a `PeriscopeStore` also uninstalls that store's
  journal. Guard: `PeriscopeTests.removalDeliversAndFlushesWhatTheSinkWasOwed`.
- **Remote export is explicit opt-in per event.** Safe sinks use
  `remoteMessage` and `remoteFields`; never infer from payloads, tags, dynamic
  scopes, ambient state, external IDs, or attachments. Attachment bytes are
  never a remote-export input, including Debug full-metadata mode.
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
- **Periscope storage is local-only.** Every on-disk `ModelConfiguration`
  explicitly sets `cloudKitDatabase: .none`; a host app's iCloud entitlement
  must never opt the logging schema into CloudKit implicitly.
- **Payloads persist as versioned JSON** (`eventName` + `eventVersion`) — an
  event shape change must not require a SwiftData migration. While the app is
  pre-release, shape changes need no decode tolerance either: the store is
  deleted rather than migrated, so keep `Codable` conformances synthesized
  instead of hand-writing defaults for older rows.
- **A session names its build only as far as the app told it.**
  `LogSession.attributes` is filled by the host app at bootstrap —
  PeriscopeCore sits below the app modules and cannot read a build stamp. An
  unstamped bundle yields an empty dictionary; nothing here invents a
  placeholder, because a session claiming it was built from a commit named
  `unknown` is worse than one that admits it can't say.
- **Keep `PeriscopeStore.inspectorModelTypes`, `inspectorStoreURL`, and
  `inspectorRecoveryStorageURLs` identical to the live store and journal
  locations.** They are the adapters that let a standalone Inspector enumerate
  or recover internal storage without starting the logging pipeline.
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
- **The relaunch sweep decides from a column, and says so when it can't.**
  `SDLogEvent.spanRelaunchPolicy` carries `SpanRelaunchPolicy` on began rows,
  so the launch-path sweep filters survivors without loading a payload; a
  payload that won't decode only costs the synthetic end its recorded name —
  and the decode failure is logged, never silently absorbed.

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost`
(`PeriscopeCoreTests`). Use in-memory stores, fresh `Periscope` systems per
test (never the shared singleton), and injected clocks. `Log<Event>()`
defaults to `.shared` — a deliberate ergonomics exception to the
no-Core-defaults rule — so tests must always pass `system:` explicitly.
