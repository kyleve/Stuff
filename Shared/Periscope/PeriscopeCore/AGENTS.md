# PeriscopeCore – Module Shape

PeriscopeCore is the core of the **Periscope** observability framework. It provides typed `Codable` log events, the `Log<Event>` scope hierarchy, tags, spans, the sink pipeline, ambient event sources, and the SwiftData store. See [`README.md`](README.md) for the narrative and API.

Read the root [`AGENTS.md`](../../../AGENTS.md) first. That file owns the build system, formatting, and global conventions.

## Scope & dependencies

- **Use Foundation, os, SwiftData, Network, CryptoKit, and JournalKit only** (plus the ObjectiveC runtime for deallocation trackers and target/selector observation. CryptoKit is used only by `ScopeID.swift`). Do not import SwiftUI or app code. Use UIKit only inside `#if canImport(UIKit)`.
- **Keep layering one-way.** `PeriscopeUI` and `PeriscopeTools` depend on this module. Never the reverse.

## Invariants

- **Emitting never blocks the caller.** Log calls append to a lock-guarded buffer synchronously.
- **Sinks drain asynchronously in emission order, scope definitions first.**
- **Observer yields happen under the state lock.** Yielding outside it lets racing emitters invert live delivery (a span's end before its began).
- **Scope IDs are deterministic** (hash of parent + name). Span pairing and cross-layer links rely on the same path being the same scope across processes and launches.
- **`sequence` is store-global and monotonic.** It resumes past the highest stored value across launches.
- **That is what makes `LogQuery.afterSequence` a valid incremental cursor.**
- **Persistence retains the full hierarchy.** Events reference scopes many-to-many. Scopes keep their parent chain.
- **Custom levels are values, not cases.** `LogLevel` is a struct ordered by `severity`. Never switch exhaustively over "all" levels.
- **Log change-only where the signal is chatty.** `NetworkPathAmbientSource` dedupes `NWPathMonitor`'s repeat callbacks.
- **Notification-based sources are deliberately not deduped.** Each repeated memory warning is a distinct event.
- **An ambient event declares whether it is a state or an occurrence.** `AmbientEvent.reporting` decides whether the event folds into the `AmbientSnapshot` stamped on later records.
- **A momentary signal (a memory warning) is `.occurrence` and never becomes state.**
- **Folding it in would leave every subsequent record claiming the app was mid-memory-warning.**
- **A source whose signal is a lasting condition must also report it at `started()`.** Otherwise the state is unknown until it next changes.
- **Thermal and low-power do.** `AppLifecycleAmbientSource` deliberately does not. It has no way to know the phase it started in.
- **Stamp ambient state at emit, not at read.** `Periscope.buffer` hands each record the snapshot in force at that moment.
- **A snapshot keeps its `id` until a `.state` event actually moves a value.**
- **That is what makes "one stored row per distinct state" true rather than one row per record.**
- **Anything that mutates the snapshot must preserve that.** A new identity per record would multiply the rows by the log volume.
- **Folding outlives the admission gates.**
- **An ambient `.state` event the level floors discard still folds into the running snapshot.** Floors route, they do not scrub.
- **One that redaction suppresses clears its kind instead.**
- **Folding it would smear the suppressed value onto every later record.** Keeping the old value would lie.
- **The snapshot must never go stale because the event itself was kept out of the record stream.**
- **`remove(_:)` is `async` because it settles the sink first.** Await the in-flight drain and flush the sink.
- **Then a removed sink is owed nothing and hears nothing more.**
- **Removing a `PeriscopeStore` also uninstalls that store's journal.** Guard: `PeriscopeTests.removalDeliversAndFlushesWhatTheSinkWasOwed`.
- **Make remote export an explicit opt-in for each event.** Safe sinks use `remoteMessage` and `remoteFields`.
- **Never infer remote data from payloads, tags, dynamic scopes, ambient state, external IDs, or attachments.**
- **Never use attachment bytes as remote-export input, including in Debug full-metadata mode.**
- **Use closed `CaseIterable` values for category fields.** Reject values outside `allCases`.
- **Sink failures never propagate or vanish.** Log them to OSLog. Count them.
- **Persist a synthetic `StoreWriteFailed` marker.** The pipeline reports drops with a synthetic `DroppedEvents` record.
- **Roll back a failed store save** (`recoverFromFailedWrite`). One poisoned batch must never wedge subsequent saves or fork the session.
- **Make the crash journal synchronous at emit and silent on failure.**
- **Every buffered record appends before `record()` returns.** Sequence is stamped under the state lock. File I/O happens outside it. Fault+ records use `F_FULLFSYNC`.
- **Journal failures count and log but never throw into the emit path.**
- **Run ingest before `startSession` so recovered begans join the orphan sweep.**
- **If a journal fails ingest, keep it for the next launch.**
- **Only app processes ingest journals.** Extensions journal their own sessions but skip ingest.
- **Ingest deletes journals.** An extension launch must not eat the live app's.
- **Concurrently live processes sharing one on-disk store is unsupported.** See [`TODOs.md`](../TODOs.md).
- **Keep Periscope storage local-only.** Every on-disk `ModelConfiguration` explicitly sets `cloudKitDatabase: .none`.
- **A host app's iCloud entitlement must never opt the logging schema into CloudKit implicitly.**
- **Persist payloads as versioned JSON** (`eventName` + `eventVersion`). An event shape change must not require a SwiftData migration.
- **While the app is pre-release, shape changes need no decode tolerance either.** The store is deleted rather than migrated.
- **Keep `Codable` conformances synthesized instead of hand-writing defaults for older rows.**
- **A session names its build only as far as the app told it.** `LogSession.attributes` is filled by the host app at bootstrap.
- **PeriscopeCore sits below the app modules and cannot read a build stamp.**
- **An unstamped bundle yields an empty dictionary.** Nothing here invents a placeholder.
- **A session claiming it was built from a commit named `unknown` is worse than one that admits it cannot say.**
- **Keep `PeriscopeStore.inspectorModelTypes`, `inspectorStoreURL`, and `inspectorRecoveryStorageURLs` identical to the live store and journal locations.**
- **They are the adapters that let a standalone Inspector enumerate or recover internal storage without starting the logging pipeline.**
- **Every span eventually ends, and its began is delivered first.**
- **`measure` closes on every path.** Bounded spans expire through the watchdog. Re-begins supersede.
- **Relaunch orphan-closes `endsWithProcess` spans.** The `survivesRelaunch` resume is staged — see [`TODOs.md`](../TODOs.md).
- **Keep all three protections:** begin registration and `SpanBegan` record land atomically (`LogRecorder.beginSpan`).
- **The overflow drop policy never splits a recorded pair** (`LogEvent.isProtectedFromDropping`).
- **Redaction is transform-only for pair records.**
- **Floor span pairs together.** Make the floor decision once, at begin (`OpenSpan.beganRecorded`, `LogRecord.bypassesFloors`).
- **A recorded began always gets its end.** A floored began silences the entire span. Never leave a dangling half.
- **Decide the relaunch sweep from a column, and say so when you cannot.**
- **`SDLogEvent.spanRelaunchPolicy` carries `SpanRelaunchPolicy` on began rows.** The launch-path sweep filters survivors without loading a payload.
- **A payload that will not decode only costs the synthetic end its recorded name.** Log the decode failure. Never silently absorb it.

## Testing

Swift Testing lives in [`Tests/`](Tests), hosted in `StuffTestHost` (`PeriscopeCoreTests`). Use in-memory stores and fresh `Periscope` systems per test (never the shared singleton). Use injected clocks. `Log<Event>()` defaults to `.shared` — a deliberate ergonomics exception to the no-Core-defaults rule — so tests must always pass `system:` explicitly.
