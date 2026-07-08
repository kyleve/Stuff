# PeriscopeCore

The core of **Periscope**, a typed, hierarchical observability framework.
Periscope logs **structured `Codable` events** (alongside freeform messages)
through **typed loggers** (`Log<Event>`) arranged in a **scope tree**, stamps
them with **tags**, times work with **spans**, and persists everything —
hierarchy included — to **SwiftData** so days or weeks of history stay
queryable on device.

PeriscopeCore owns the model and the machinery: events, levels, scopes,
links, tags, spans, attachments, the sink pipeline (OSLog + SwiftData
built-in), ambient event sources, and the store. SwiftUI integration lives in
[`PeriscopeUI`](../PeriscopeUI); the on-device viewer, tracer, toast, and
inspect mode live in [`PeriscopeTools`](../PeriscopeTools).

## Vocabulary

| Periscope term | Industry equivalent |
|----------------|---------------------|
| Scope | OTel `InstrumentationScope` — a node in the logger hierarchy |
| Link | OTel span links — one event referencing several scopes |
| Span | OTel span — a timed operation with a shared `SpanID` |
| Session | OTel `Resource` — per-launch app/OS/device metadata |
| Tag | Datadog/Jaeger tags — key/value stamped on events |

## Installation

`PeriscopeCore` is a local SPM library in this repo
(`Shared/Periscope/PeriscopeCore`). Add it to a target's dependencies in
[`Package.swift`](../../../Package.swift):

```swift
.target(name: "YourModule", dependencies: [.target(name: "PeriscopeCore")])
```

## Quick start

Define events, derive loggers, log:

```swift
import PeriscopeCore

struct PhotoLogs: LogEvent {
    var photoID: String
    var message: String { "Uploaded \(photoID)" }
}

let root = Log<AppLogs>()                  // records into Periscope.shared
let photos = root(PhotoLogs.self)          // typed child scope
let album = photos(for: album.id)          // child scope keyed by an entity

album { PhotoLogs(photoID: photo.id) }     // structured event
album.warning("thumbnail cache miss")      // freeform, any Log can
photos(for: album.id) { PhotoLogs(photoID: photo.id) } // derive + emit in one call

let joined = album + screenLog             // link model + UI contexts
let tagged = joined.tagged(.paymentID, payment.id)  // stamps every event
```

Wire persistence at startup:

```swift
let store = try await PeriscopeStore.make(storage: .onDisk, session: .current())
Periscope.shared.add(sink: store)
Periscope.shared.startDefaultAmbientSources()
```

## Public API

- **Events** — `LogEvent` (`Codable & Sendable`; `eventName`, `eventVersion`,
  `level`, `message`), the built-in freeform `Message`, and the extensible
  `LogLevel` struct (`name` + `severity`; standard ladder `debug…fault`,
  custom levels slot between).
- **Loggers** — `Log<Event>`: derive typed children (`log(PhotoLogs.self)`),
  entity children (`log(for: id)`), link contexts (`+` / `linked(with:)`),
  tag (`tagged(_:_:)`), and emit (trailing closure, level conveniences,
  `attachments:`). Scope IDs are deterministic (parent + name), so the same
  path is the same scope in any process or launch.
- **Propagation** — `log.withContext { … }` binds the context to a
  `@TaskLocal`; `Log<E>.current` reads it anywhere in the async call tree.
  `LogContextProviding` gives classes a derived per-instance `.log`.
- **Spans** — `log.measure(.token) { … }` (sync/async) emits paired
  `SpanBegan`/`SpanEnded` events with the exit derived automatically
  (return → `.success`, throw → `.failure`, `CancellationError` →
  `.cancelled`), and an optional `budget:` fires a `SpanOverdue` warning
  while the closure hangs past it; `begin(for:lifetime:relaunch:)`/
  `end(for:exit:)` for open-ended spans. Every span provably ends: bounded spans expire past
  their budget (watchdog, `.expired`), re-begins supersede the open span
  (`.superseded`), and a relaunch closes `endsWithProcess` spans the dead
  process left open (`.orphaned`, duration unknowable). Durations use
  `ContinuousClock`; spans mirror to `OSSignposter`.
- **Attachments** — `LogAttachment` (+ `.error`, `.json`, `.image`
  conveniences) rides along with any event; blobs persist externally and
  load on demand.
- **System** — `Periscope`: the recorder and `LogSink` pipeline (OSLog sink
  built in), level floors (`minimumLevel`, `setMinimumLevel(_:forSubtree:)`),
  flush threshold, bounded drop policy with synthetic `DroppedEvents`,
  redaction hook, recent buffer + `liveRecords()` stream, ambient
  sources (`startAmbientSource`, `startDefaultAmbientSources`), and the
  `isInspectModeEnabled` flag behind PeriscopeTools' log view mode.
- **Store** — `PeriscopeStore` (`@ModelActor` `LogSink`): sessions
  (`LogSession`), `events(matching: LogQuery)` (time range, level floor,
  event name, session, scope/subtree, tag, search, paging),
  `events(inSpan:)`, `attachments(forEvent:)`, retention
  (`pruneEvents(olderThan:/keepingNewest:)`), and a `changes()` signal.

## How it works

Log call sites never block: records append to a lock-guarded pending queue
and a background drain task delivers ordered batches to each sink (scope
definitions always precede the records referencing them). Error-and-above
events trigger an automatic flush; queue overflow drops oldest and reports
the gap (scope definitions and span began/ended pairs are exempt). Event payloads persist as JSON keyed by `eventName` + `eventVersion`
so old rows outlive their Swift types — `StoredLogEvent.decode(_:)` recovers
the type, and tooling degrades to raw JSON when it can't.

## Contracts & limitations

- Messages mirror to OSLog as `.public` — keep PII out of messages, or scrub
  via the redaction hook. The hook may transform any record but cannot
  suppress span began/ended records (a stripped copy records instead —
  pairs never split); silence spans with level floors.
- One database for every logging system in the process; scopes and types
  make it easy to split later.
- `LogContextProviding` caches one small entry per logging instance, evicted
  automatically when the instance deallocates (a tracker hangs off the
  instance via the ObjC runtime). Instance numbers (`#1`, `#2`, …) are never
  reused within a run, so persisted identities stay unambiguous.

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost`
(`PeriscopeCoreTests` bundle). Tests use fresh `Periscope` systems, in-memory
stores (`@_spi(Testing) PeriscopeStore.inMemory`), and condition polling —
run with `tuist test PeriscopeCoreTests`.
