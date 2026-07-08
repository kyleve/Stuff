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

> **Status:** scaffolding. The API below lands incrementally; sections are
> filled in as each piece ships.

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

## Public API

Landing incrementally — see the sources for what exists today.

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost`
(`PeriscopeCoreTests` bundle). Tests use in-memory stores and injected
clocks; run with `tuist test PeriscopeCoreTests`.
