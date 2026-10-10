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
[`PeriscopeUI`](../PeriscopeUI). The on-device viewer, tracer, toast, and
inspect mode live in [`PeriscopeTools`](../PeriscopeTools).

## Vocabulary

| Periscope term | Industry equivalent |
|----------------|---------------------|
| Scope | OTel `InstrumentationScope` — a node in the logger hierarchy |
| Link | OTel span links — one event referencing several scopes |
| Span | OTel span — a timed operation with a shared `SpanID` |
| Session | OTel `Resource` — per-launch app/OS/device/build metadata |
| Tag | Datadog/Jaeger tags — typed key/value (`LogTagValue`: string, int, double, bool, or any `Codable` via `.encoding`) stamped on events |
| Ambient snapshot | No direct equivalent — the system state (network, thermal, power, lifecycle) as of one event |

## Installation

`PeriscopeCore` is a local SPM library in this repo
(`Shared/Periscope/PeriscopeCore`). Add it to a target's dependencies in
[`Package.swift`](../../../Package.swift):

```swift
.target(name: "YourModule", dependencies: [.target(name: "PeriscopeCore")])
```

## Quick start

The classified API supports `@LogField(exposure: .shareable, kind: .count)` without an explicit key.
The macro converts the property name to an ASCII snake-case key.
Exposure and kind remain mandatory.
See the [macro authoring guide](../PeriscopeMacros/README.md) for key inference and rename rules.

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
// `attributes` is how the app names its own build — Periscope sits below the
// app modules, so it can't read the build stamp itself. See
// `LogSessionAttributeKey` for the well-known keys.
let session = LogSession.current(attributes: BuildInfo.current(bundle: .main).logSessionAttributes)
let store = try await PeriscopeStore.make(storage: .onDisk, session: session)
Periscope.shared.add(sink: store)
Periscope.shared.startDefaultAmbientSources()
```

## Structured errors

Declare an error field as `LogError` with `.restricted/.errorDetails`.
Pass the original error at emission:

```swift
log.persistBacklogFailed(error: .restricted(.errorDetails, error))
```

The classified input captures a snapshot before the log call returns.
The snapshot preserves the domain, numeric code, localized description, failure reason, recovery suggestion, and underlying causes.
Decoding errors also preserve their failure kind and coding path, including numeric array indices.
The snapshot does not reconstruct the original error type. Services and failure state retain the original `Error`.

Capture stops at eight levels or 32 nodes, including the root.
A cycle or limit leaves an explicit omission marker and stops the remaining causes at that node.
The snapshot never copies arbitrary `NSError.userInfo` or reflects stored properties.

Use concrete event fields for domain-specific data with a known schema.
For explicitly selected Codable diagnostics, convert them before emission:

```swift
let snapshot = try LogError(capturing: error, details: .encoding(diagnostics))
log.persistBacklogFailed(error: .restricted(.errorDetails, snapshot))
```

Conversion throws on failure. The caller must handle that error, not replace the details with an empty value.
Baseline export excludes error snapshots. Diagnostic export filters their structured payloads.
Codes, cause structure, omission markers, and decoding kinds need no personal-data grant in diagnostic mode.
Domains, descriptions, coding paths, and caller-supplied details require the personal-data control.
Restricted does not mean local-only. Attachment bytes remain excluded from every remote mode.

## Export controls

`LogExportPolicy` separates the export mode from independent data permissions.
`LogExportControl` is an extensible value type, not a closed enum.
Consumers declare controls with stable, namespaced identifiers:

```swift
extension LogExportControl {
    static let myExportControl = Self("com.example.my-export-control")
}

var policy = LogExportPolicy(mode: .diagnostic, enabledControls: [])
policy[.location] = true
policy[.myExportControl] = true
```

The built-in controls cover identifiers, location, user content, and other personal data.
Each control is independent. The personal-data control is not a wildcard.
Diagnostic mode does not enable any control automatically.

A host can present one switch for an explicit group:

```swift
let personalControls: Set<LogExportControl> = [
    .identifiers, .location, .userContent, .personalData,
]
policy.setEnabled(includePersonalData, for: personalControls)
```

This operation preserves unrelated grants. New framework controls and consumer controls remain off until explicitly enabled.
The host owns labels, explanations, and the group membership shown in its UI.

`LogExportRequirements` describes author-approved eligibility and required controls:

```swift
let requirements = LogExportRequirements.diagnostic(requiring: [.location, .myExportControl])
let canExport = policy.allows(requirements)
```

Every required control must be enabled. A child uses `constrained(by:)` to retain its parent's restrictions.
The `.never` requirement denies export regardless of the mode or enabled controls.
These declarations express approval. They do not inspect values for personal data.

`@LogEvent` generates `exportedValue(using:)`. Denied fields do not invoke their encoder.
Local `Codable` persistence remains complete. Raw encoding is not an export API.
Manual event conformances default to an empty export object.

Restricted fields can override their diagnostic requirements:

```swift
@LogField(exposure: .restricted, kind: .identifier, export: .never)
var credentialID: String

@LogField(exposure: .restricted, kind: .domainValue,
          export: .diagnostic(requiring: [.myExportControl]))
var diagnostics: DiagnosticDetails
```

Shareable fields already approve baseline export and cannot declare an export override.
Restricted identifiers, locations, and user content require their respective controls.
Restricted scalar operational kinds need diagnostic mode. Other restricted values require personal-data consent by default.
`LogError` fields use the nested error projection instead of a blanket text approval.

Nested types implement `LogExportable` to filter their members with `LogExportField.object(_:using:)`.
Optional values, arrays, and string-keyed dictionaries preserve nested projections.
The containing field must pass its own requirements before any child can export.
Opaque Codable values and `JSONValue` are atomic: their containing field approves their complete contents, including dictionary keys.
Do not wrap policy-bearing values in opaque Codable containers or pre-encode them as JSON. Preserve their `LogExportable` projection instead.

## Public API

- **Events** — `LogEvent` (`Codable & Sendable`; `eventName`, `eventVersion`,
  `level`, `message`, PII-free `remoteMessage`, approved `remoteFields`), the built-in freeform `Message`, and the extensible
  `LogLevel` struct (`name` + `severity`; standard ladder `debug…fault`,
  custom levels slot between).
- **Loggers** — `Log<Event>`: derive typed children (`log(PhotoLogs.self)`),
  entity children (`log(for: id)`), link contexts (`+` / `linked(with:)`),
  tag (`tagged(_:_:)`), and emit (trailing closure, level conveniences,
  `attachments:`). Scope IDs are deterministic (parent + name), so the same
  path is the same scope in any process or launch.
- **Propagation** — `log.withContext { … }` binds the context to a
  `@TaskLocal`. `Log<E>.current` reads it anywhere in the async call tree.
  `LogContextProviding` gives classes a derived per-instance `.log`.
- **Spans** — `log.measure(.token) { … }` (sync/async) emits paired
  `SpanBegan`/`SpanEnded` events with the exit derived automatically
  (return → `.success`, throw → `.failure`, `CancellationError` →
  `.cancelled`), and an optional `budget:` fires a `SpanOverdue` warning
  while the closure hangs past it. Names resolve against `Event.SpanName`
  (defaults to `String`). Declare a `SpanName` enum on the event type for
  compiler-checked tokens — the recommended style for structured events.
  Open-ended flows use `begin(for:lifetime:relaunch:)`/`end(for:exit:)`.
  Every span provably ends: bounded spans expire past
  their budget (watchdog, `.expired`), re-begins supersede the open span
  (`.superseded`), and a relaunch closes `endsWithProcess` spans the dead
  process left open (`.orphaned`, duration unknowable). Durations use
  `ContinuousClock`. Spans mirror to `OSSignposter`.
- **Structured errors** — `LogError` captures typed diagnostics as a restricted event field. See [Structured errors](#structured-errors).
- **Attachments** — `LogAttachment` (+ `.error`, `.json`, `.image`
  conveniences) rides along with any event. Blobs persist externally and
  load on demand.
- **Remote approval** — `remoteMessage` defaults to the stable event name and
  `remoteFields` defaults empty. Fields are restricted to booleans, counts,
  durations, and closed `RawRepresentable & CaseIterable` categories whose
  selected value must be one of `allCases`; safe sinks never infer from the
  Codable payload, tags, dynamic scopes, ambient state, external IDs, or attachments.
  Debug full-metadata mode may add that context plus attachment names/MIME
  types, but attachment bytes are never a remote-export input.
- **System** — `Periscope`: the recorder and `LogSink` pipeline (OSLog sink
  built in; `add(sink:)` returns a `SinkToken` that `remove(_:)` detaches —
  see [Detaching a sink](#detaching-a-sink)), level floors (`minimumLevel`,
  `setMinimumLevel(_:forSubtree:)`),
  flush threshold, bounded drop policy with synthetic `DroppedEvents`,
  redaction hook, recent buffer + `liveRecords()` stream, ambient
  sources (`startAmbientSource`, `startDefaultAmbientSources`,
  `stopAmbientSources`), and the `isInspectModeEnabled` flag behind
  PeriscopeTools' log view mode.
- **Ambient state** — `AmbientEventSource`s report what the system is doing
  (`NetworkPathAmbientSource`, thermal, low-power, lifecycle, memory
  warnings, accessibility). Each `AmbientLogEvent` projects its local state as named
  fields (`[String: AmbientValue]` — a plain JSON object in the payload,
  e.g. `["status": "satisfied", "voiceover": false]`) and declares its
  `reporting`: a `.state` event is a lasting condition, an `.occurrence` a
  momentary one (a memory warning). The pipeline folds the `.state` events
  into an `AmbientSnapshot` and stamps it on **every** record — so any error
  joins to the connectivity, thermal state, and power mode at that moment
  without a timestamp hunt.
  Named built-in events approve lifecycle phases, thermal conditions, power mode,
  memory warnings, and connectivity for baseline export. Network interfaces,
  accessibility settings, and custom `AmbientLog.Event` payloads remain restricted.
  A custom event never inherits approval from its `AmbientKind`.
  These approvals deliberately expand the previous ambient export boundary.
  The snapshot itself remains local and is excluded from baseline export.
  Sources receive `Log<AmbientLog>`. Notification adapters return
  `any AmbientLogEvent & LogEvent` so the same folding path handles every event type.
  Built-ins now use distinct `ambient.*` event names and payload shapes.
  This is a deliberate wire break, without historical typed-decode compatibility.
- **Session attributes** — `LogSession.current(attributes:)` takes
  `[LogSessionAttributeKey: String]`, the build facts only the app can name:
  `.commit` / `.commitStatus`, `.configuration`, `.optimizationLevel`,
  `.compilationMode`. The optimization level is the load-bearing one — a
  span duration from an `-Onone` build says nothing about the shipping app,
  and the configuration alone can't answer it (a `Debug` configuration can
  be compiled `-O`).
- **Store** — `PeriscopeStore` (`@ModelActor` `LogSink`): sessions
  (`LogSession`, plus `currentSession` for this launch),
  `events(matching: LogQuery)` (time range, level floor,
  event name, session, scope/subtree, tags (AND), search, an incremental
  `afterSequence` cursor, paging), `events(inSpan:)`,
  `attachments(forEvent:)`, `ambientSnapshot(for:)` /
  `ambientSnapshots()`, retention
  (`pruneEvents(olderThan:/keepingNewest:)`), and a `changes()` signal.
  `makeContainer(storage:)`, `inspectorModelTypes`, `inspectorStoreURL`, and
  `inspectorRecoveryStorageURLs` expose the narrow schema adapter a standalone
  Inspector runtime needs without starting a logging session or exposing the
  internal SwiftData model classes. The recovery URLs include the crash
  journals that would otherwise replay deleted history into a fresh store.
  Periscope storage is always local-only. its model configurations disable
  CloudKit explicitly even when the host application has iCloud entitlements.

## How it works

Log call sites never block: records append to a lock-guarded pending queue
and a background drain task delivers ordered batches to each sink (scope
definitions always precede the records referencing them). Error-and-above
events trigger an automatic flush. queue overflow drops oldest and reports
the gap (scope definitions and span began/ended pairs are exempt). Event payloads persist as JSON keyed by `eventName` + `eventVersion`
so old rows outlive their Swift types — `StoredLogEvent.decode(_:)` recovers
the type, and tooling degrades to raw JSON when it can't.

Ambient state is stamped at buffer time, not resolved at read time: the
pipeline keeps the current `AmbientSnapshot` and hands each record the one in
force when it was emitted. A snapshot keeps its identity until a `.state`
event actually moves a value, so a run of records under one system state
shares one identity — and the store persists one row per *distinct* state
that events reference by ID, rather than a copy per event.

### Detaching a sink

Most apps add their sinks once and keep them for the process, so `add(sink:)`'s
`SinkToken` is `@discardableResult`. Detach one with `await
system.remove(token)`, which settles the sink before letting go: it leaves the
registry under the lock (so no later drain sees it), the call awaits any drain
already mid-delivery, and the sink is flushed. When it returns, the sink has
everything emitted before the call and will receive nothing after it.

Removing a `PeriscopeStore` also uninstalls the crash journal that store
installed, since the journal is the emit-side tap belonging to a store now out
of the pipeline. The token — not the sink — is the identity removed, so one of
two registrations of the same sink can be detached (`LogSink` isn't
class-constrained, so a value sink has no identity of its own).

The Where app uses this for its in-memory demo mode: entering swaps the durable
on-disk store sink for an in-memory one, and exiting swaps back.

**Crash durability**: on-disk stores also open a per-session journal
([JournalKit](../../JournalKit)) beside the database, and once the store is
added as a sink, every record appends to it *synchronously* at emit
(microseconds — a page-cache write that survives the process dying by any
means. fault-level records `F_FULLFSYNC` for kernel-panic coverage). The
journal does **not** yet cover the whole process lifetime: it opens with the
store, and `PeriscopeStore.make` is `async`, so records emitted between
process launch and `add(sink:)` — early launch steps, ambient start-up
snapshots — reach neither the store nor a journal. They survive only in the
recent buffer and OSLog. Closing that window (a bootstrap journal from
process start, ingested when the store attaches) is tracked in
[`TODOs.md`](../TODOs.md). At the
next launch the store ingests prior journals before the session starts:
undelivered records persist (deduplicated by event ID), recovered span
begans join the orphan sweep, a `.notice` marks the recovery, and the
journal is deleted. The loss window at a hard crash is the microseconds
between a record buffering and its append returning. In-memory stores
never journal, and only app processes ingest — app extensions journal
their own sessions and leave recovery to the app's next launch.

## Contracts & limitations

- Messages mirror to OSLog as `.public` — keep PII out of messages, or scrub
  via the redaction hook. The hook may transform any record but cannot
  suppress span began/ended records (a stripped copy records instead — pairs
  never split). Silence spans with level floors.
- One database for every logging system in the process. Scopes and types
  make it easy to split later.
- `LogContextProviding` caches one small entry per logging instance, evicted
  automatically when the instance deallocates (a tracker hangs off the
  instance via the ObjC runtime). Instance numbers (`#1`, `#2`, …) are never
  reused within a run, so persisted identities stay unambiguous.

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost`
(`PeriscopeCoreTests` bundle). Tests use fresh `Periscope` systems, in-memory
stores (`@_spi(Testing) PeriscopeStore.inMemory`), and condition polling — 
run with `./test PeriscopeCoreTests`.
